package OpenCloset::Cron::Event;

require Exporter;
@ISA       = qw/Exporter/;
@EXPORT_OK = qw/update_employment_wing_status/;

use strict;
use warnings;

use OpenCloset::Events::EmploymentWing;
use OpenCloset::Constants::Status qw/
    $NOT_VISITED
    $RESERVATED
    $RENTAL
    $RETURNED/;

=encoding utf8

=head1 NAME

OpenCloset::Cron::Event - 이벤트와 관련된 예약작업

=head1 SYNOPSIS

    perl bin/opencloset-cron-event.pl /path/to/app.conf

=head1 DESCRIPTION

=head1 METHODS

=head2 update_employment_wing_status( $schema, $date, $status )

    use OpenCloset::Events::EmploymentWing qw/$EW_STATUS_COMPLETE/;
    ...
    update_employment_wing_status($schema, $account, $date, $EW_STATUS_COMPLETE);

C<$ymd> 일 취업날개를 통해 예약한 방문자의 예약상태를 변경

=head3 Notice

C<$rent_num> 없이 예약된 경우도 있음

예로 2017/5/21일 취업날개로 예약하고 2017/5/23일 대여했다면 rent_num 없이 대여됨

    seoul-2017-2|xxxxxxxxxxxx-xxx|xxxxxxxxxx    # OK
    seoul-2017|xxxxxxxxxx                       # OK

=cut

sub update_employment_wing_status {
    my ( $schema, $date, $status ) = @_;

    my $client = OpenCloset::Events::EmploymentWing->new;
    my $rs     = $schema->resultset('Order')->search(
        {
            'me.online'     => 0,
            'me.status_id'  => { 'not in' => [ $NOT_VISITED, $RESERVATED ] },
            'coupon.status' => 'used',
            'coupon.desc' => { -like => 'seoul-2018%' },
        },
        {
            select => ['coupon.desc'],
            as     => ['desc'],
            join   => [ 'booking', 'coupon' ]
        }
    )->search_literal( 'DATE(`booking`.`date`) = ?', $date->ymd );

    my %count = ( success => 0, fail => 0 );
    while ( my $row = $rs->next ) {
        my $desc = $row->get_column('desc');
        my ( $event, $rent_num, $mbersn ) = split /\|/, $desc;
        next if $event eq 'seoul-2018';

        my $success = $client->update_status( $rent_num, $status );

        unless ($success) {
            printf STDERR "[%s] Failed to update status to %d: %s", $date->ymd, $EW_STATUS_COMPLETE, $desc;

            $count{fail}++;
            sleep(1);
            next;
        }

        $count{success}++;
        sleep(1);
    }

    $rs = $schema->resultset('Order')->search(
        {
            'me.online'      => 1,
            'me.rental_date' => {
                -between => [
                    $date->datetime,
                    $date->clone->add( days => 1 )->subtract( seconds => 1 )->datetime
                ]
            },
            'me.status_id' => { -in => [ $RENTAL, $RETURNED ] }, # 대여중 혹은 반납
            'coupon.status' => 'used',
            'coupon.desc'   => { -like => 'seoul-2018%' },
        },
        {
            select => [ 'coupon.desc', 'rental_date' ],
            as     => [ 'desc',        'rental_date' ],
            join   => 'coupon'
        }
    );

    while ( my $row = $rs->next ) {
        my $desc = $row->get_column('desc');
        my ( $event, $rent_num, $mbersn ) = split /\|/, $desc;
        next if $event eq 'seoul-2018';

        my $success = $client->update_status( $rent_num, $status );

        if ($success) {
            my $rental_date = $row->rental_date;
            $client->update_booking_datetime( $rent_num, $rental_date, 1 );
        }
        else {
            printf STDERR "[%s] Failed to update status to %d: %s", $date->ymd, $EW_STATUS_COMPLETE, $desc;

            $count{fail}++;
            sleep(1);
            next;
        }

        $count{success}++;
        sleep(1);
    }

    return \%count;
}

1;

=head1 COPYRIGHT and LICENSE

The MIT License (MIT)

Copyright (c) 2018 열린옷장

=cut
