use utf8;
use strict;
use warnings;

use FindBin qw( $Script );
use Getopt::Long::Descriptive;

use DateTime;

use OpenCloset::Config;
use OpenCloset::Cron::Event qw/update_employment_wing_status/;
use OpenCloset::Cron::Worker;
use OpenCloset::Cron;
use OpenCloset::Events::EmploymentWing qw/$EW_STATUS_COMPLETE/;
use OpenCloset::Schema;

my $config_file = shift;
die "Usage: $Script <config path>\n" unless $config_file && -f $config_file;

my $CONF     = OpenCloset::Config::load($config_file);
my $APP_CONF = $CONF->{$Script};
my $DB_CONF  = $CONF->{database};
my $TIMEZONE = $CONF->{timezone};

die "$config_file: $Script is needed\n"  unless $APP_CONF;
die "$config_file: database is needed\n" unless $DB_CONF;
die "$config_file: timezone is needed\n" unless $TIMEZONE;

my $DB = OpenCloset::Schema->connect(
    { dsn => $DB_CONF->{dsn}, user => $DB_CONF->{user}, password => $DB_CONF->{pass}, %{ $DB_CONF->{opts} }, } );

my $worker1 = do {
    my $w;
    $w = OpenCloset::Cron::Worker->new(
        name      => 'daily_update_employment_wing_status', # 일일 취업날개 방문자 예약상태 변경 for 통합통계
        cron      => '05 01 * * *',
        time_zone => $TIMEZONE,
        cb        => sub {
            my $name = $w->name;
            my $cron = $w->cron;
            AE::log( info => "$name\[$cron] launched" );

            my $today = DateTime->today( time_zone => $TIMEZONE );
            my $date = $today->clone->subtract( days => 1 );
            my $count = update_employment_wing_status( $DB, $date, $EW_STATUS_COMPLETE );
            AE::log( info => sprintf( "%s success: %d, fail: %d", $date->ymd, $count->{success}, $count->{fail} ) );
        }
    );
};

my $cron = OpenCloset::Cron->new(
    aelog   => $APP_CONF->{aelog},
    port    => $APP_CONF->{port},
    delay   => $APP_CONF->{delay},
    workers => [$worker1],
);

$cron->start;
