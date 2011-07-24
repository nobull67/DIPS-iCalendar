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

my $ics_file;

sub begin_calendar {
    open $ics_file, '>', shift().'.ics' or die $!;
    select $ics_file;
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
}

sub end_calendar {
    say "END:VCALENDAR";
    select *STDOUT;
    close $ics_file;
}

sub duty {
    my ($duty,$from,$until) = @_;

    say "BEGIN:VEVENT";

    my $end = $duty->{'until'};
    my $start = $duty->{from};
    my $summary = $duty->{Event};

    # If the members times differ from the duty then put the duty time on the 
    if ($from && "$from$until" ne "$start$end" ) {
	$summary .= " ($start-$end)";
	$start = $from;
	$end = $until;
    }
    my $date = $duty->{date};
    $date =~ s/^(\d\d)\/(\d\d)\/(\d\d\d\d)$/$3$2$1/ or die;

    $end =~ s/^(\d\d):(\d\d)$/${date}T$1${2}00/ or die;
    say "DTEND;TZID=UK:$end";

    say "DTSTAMP:20110715T181550Z";

    $start =~ s/^(\d\d):(\d\d)$/${date}T$1${2}00/ or die;
    say "DTSTART;TZID=UK:$start";

    my $loc = join ', ' => grep { length } @$duty{(sort grep { /^DutyAddress/ } keys %$duty),'DutyPostCode' };
    say "LOCATION:",qu($loc);

    say "SUMMARY:",qu($summary);
    
    say "UID:$duty->{external_id}\@duties.org/DIPS-iCalendar";
    say "END:VEVENT";
}

my $input_file = 'Scrape-DIPS.dat';

GetOptions( 'file=s' => \$input_file,
    );

my $duties = @{retrieve($input_file)}{'duties'};

# Get lists of members and units (unfortunately don't have members IDs)

my %units;
for my $duty ( @$duties ) {
    my $external_id = $duty->{external_id};
    for my $d ( @{$duty->{divisions}} ) {
	my $u = \%{$units{$d->{division_code}}};
	$u->{name} = $d->{division_name};
	$u->{duties}{$external_id} = $duty;
    }
    for my $m ( @{$duty->{members}} ) {
	# Handly back link in member
	$m->{duty} = $duty;
	my $u = \%{$units{$m->{division_code}}};
	$u->{name} ||= $m->{division_name};
	#$u->{duties}{$external_id} = $duty;
	push @{$u->{members}{$m->{name}}{duties}} => $m;
    }
}

for my $division_code ( sort keys %units ) {
    my $u = $units{$division_code};
    begin_calendar($division_code);
    for my $external_id ( sort keys %{$u->{duties}} ) {
	duty $u->{duties}{$external_id};
    }
    end_calendar;
    for my $member_name ( sort keys %{$u->{members}} ) {
	begin_calendar("$division_code $member_name");
	for my $m ( @{$u->{members}{$member_name}{duties}} ) {
	    duty @$m{'duty','from','until'};
	}
	end_calendar;
    }
}


