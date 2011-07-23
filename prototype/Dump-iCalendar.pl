use strict;
use warnings;
use Data::Dumper;
use Storable;
use 5.10.0;
use Getopt::Long;
use POSIX qw( strftime );

sub qu {
    my $s = shift;
    $s =~ s/([,;\\])|(\n)/ $2 ? "\\n" : "\\$1" /eg;
    $s;
}

my $input_file = 'Scrape-DIPS.dat';
my $output_file = 'Scrape-DIPS.ics';

GetOptions( 'file=s' => \$input_file,
	    'out=s' => \$output_file,
    );

my $duties = @{retrieve($input_file)}{'duties'};

open my $output_fh, '>', $output_file or die $!;
select $output_fh;

say "BEGIN:VCALENDAR";
say "PRODID:-//Brian.McCauley\@kings-norton.sja.org.uk//DIPS-iCalendar 0.01//EN";
say "VERSION:2.0";
say "METHOD:PUBLISH";
say "BEGIN:VTIMEZONE";
say "TZID:UK";
say "BEGIN:STANDARD";
say "DTSTART:16011028T020000";
say "RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10";
say "TZOFFSETFROM:+0100";
say "TZOFFSETTO:-0000";
say "END:STANDARD";
say "BEGIN:DAYLIGHT";
say "DTSTART:16010325T010000";
say "RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3";
say "TZOFFSETFROM:-0000";
say "TZOFFSETTO:+0100";
say "END:DAYLIGHT";
say "END:VTIMEZONE";

for my $duty ( @$duties ) {

    say "BEGIN:VEVENT";

    my $date = $duty->{date};
    $date =~ s/^(\d\d)\/(\d\d)\/(\d\d\d\d)$/$3$2$1/ or die;

    my $end = $duty->{'until'};
    $end =~ s/^(\d\d):(\d\d)$/${date}T$1${2}00/ or die;
    say "DTEND;TZID=UK:$end";

    say "DTSTAMP:20110715T181550Z";

    my $start = $duty->{from};
    $start =~ s/^(\d\d):(\d\d)$/${date}T$1${2}00/ or die;
    say "DTSTART;TZID=UK:$start";

    my $loc = join ', ' => grep { length } @$duty{(sort grep { /^DutyAddress/ } keys %$duty),'DutyPostCode' };
    say "LOCATION:",qu($loc);

    say "SUMMARY:",qu($duty->{Event});
    
    say "UID:$duty->{external_id}\@duties.org/DIPS-iCalendar";
    say "END:VEVENT";
}

say "END:VCALENDAR";
