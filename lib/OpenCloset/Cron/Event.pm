package OpenCloset::Cron::Event;

require Exporter;
@ISA       = qw/Exporter/;
@EXPORT_OK = qw/update_employment_wing_status/;

use strict;
use warnings;

use OpenCloset::Events::EmploymentWing;
use OpenCloset::Constants::Status qw/$NOT_VISITED $RESERVATED/;

=encoding utf8

=head1 NAME

OpenCloset::Cron::Event - 이벤트와 관련된 예약작업

=head1 SYNOPSIS

    perl bin/opencloset-cron-event.pl /path/to/app.conf

=head1 DESCRIPTION

=head1 METHODS

=head2 update_employment_wing_status( $account, $date, $status_to )

    use OpenCloset::Events::EmploymentWing qw/$EW_STATUS_COMPLETE/;
    ...
    update_employment_wing_status({ username => 'xxxx', password => 'xxxx' }, $date, $EW_STATUS_COMPLETE);

C<$ymd> 일 취업날개를 통해 예약한 방문자의 예약상태를 변경

=head3 Notice

C<$rent_num> 없이 예약된 경우도 있음

예로 2017/5/21일 취업날개로 예약하고 2017/5/23일 대여했다면 rent_num 없이 대여됨

    seoul-2017-2|xxxxxxxxxxxx-xxx|xxxxxxxxxx    # OK
    seoul-2017|xxxxxxxxxx                       # OK

=cut

sub update_employment_wing_status {
    my ( $schema, $account, $date, $status ) = @_;

    my $client = OpenCloset::Events::EmploymentWing->new(
        username => $account->{username},
        password => $account->{password},
    );

    die "Failed to sign in 취업날개 관리서비스" unless $client;
    return unless $client;

    my $rs = $schema->resultset('Order')->search(
        {
            'me.status_id'  => { 'not in' => [ $NOT_VISITED, $RESERVATED ] },
            'coupon.status' => 'used',
            'coupon.desc' => { -like => 'seoul-2017%' },
        },
        {
            select => ['coupon.desc'],
            as     => ['desc'],
            join   => [ 'booking', 'coupon' ]
        }
    )->search_literal( 'DATE(`booking`.`date`) = ?', $date->ymd );

    my %count;
    while ( my $row = $rs->next ) {
        my $desc = $row->get_column('desc');
        my ( $event, $rent_num, $mbersn ) = split /\|/, $desc;
        next if $event eq 'seoul-2017';

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

    return \%count;
}

1;

=head1 COPYRIGHT and LICENSE

The MIT License (MIT)

Copyright (c) 2017 열린옷장

=cut
