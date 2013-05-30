use strict;
use warnings;
use Data::Dumper;
use Storable;
use v5.14;
use Getopt::Long;
use POSIX qw( strftime );
use Time::Local;

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;

sub qu {
    my $s = shift;
    $s =~ s/([,;\\])|(\n)/ $2 ? "\\n" : "\\$1" /eg;
    $s;
}

sub parse_date_to_noon {
    return unless my $date = shift;
    # Must adjust the date for the end time past midnight
    my ($d,$m,$y) = $date =~ /(\d+)/g;
    timegm 0, 0, 12, $d-0, $m-1, $y-1900;
};

sub fixup_dates {
    my $d = shift;
    # warn Dumper $d;
    s/^(\d\d):(\d\d)$/$1${2}00/ or die
	for my($from,$until)=@$d{'StartTime','EndTime'};

    my $noon = parse_date_to_noon($d->{StartDate});
    $d->{start} = strftime "%Y%m%dT$from", gmtime $noon;
    $noon = parse_date_to_noon($d->{EndDate}) || 
	$noon + ( $until lt $from ? 86400 : 0);
    $d->{end} = strftime "%Y%m%dT$until", gmtime $noon;
}    

# Transform YYYYMMDDTHHMMSS to YYYY-MM-DD HH:MM
sub df {
    shift =~ /^(\d\d\d\d)(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d)$/ or die;
    "$1-$2-$3 $4:$5";
}

my $ics_file;

open my $csv_file,'>','duties.csv' or die $!;

sub csv {
   #die Dumper \@_;
   no warnings 'uninitialized';
   say $csv_file join(',',map{"\"$_\""} @_);
}

sub begin_calendar {
    open $ics_file, '>', shift().'.ics' or die $!;
    select $ics_file;
    say "BEGIN:VCALENDAR";
    say "PRODID:-//Brian.McCauley\@sja.org.uk//DIPS-iCalendar 0.02//EN";
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
    my ($duty,$start1,$end1,$id) = @_;

    say "BEGIN:VEVENT";

    $id ||= "duty-$duty->{internal_id}";
    my $end = $duty->{end};
    my $start = $duty->{start};
    my $summary = $duty->{Event};

    # If the members times differ from the duty then put the duty time on the 
    if ($start1 && "$start1$end1" ne "$start$end" ) {
	if ( substr($start,0,6) eq substr($start1,0,6) ) {
	    $summary .= " ($duty->{StartTime}-$duty->{EndTime})";
	} else {
	    # Not even same day!
	    $summary .= " ($duty->{StartDate} $duty->{StartTime}-$duty->{EndTime})";

	    $start = $start1;
	    $end = $end1;
	}
    }
    my $date = $duty->{date};

    say "DTEND;TZID=UK:$end";
    say "DTSTAMP:20110715T181550Z";
    say "DTSTART;TZID=UK:$start";

    my $loc = join ', ' => grep { length } @$duty{(sort grep { /^DutyAddress/ } keys %$duty),'DutyPostCode' };
    say "LOCATION:",qu($loc);

    say "SUMMARY:",qu($summary);

    say "UID:$id\@dips.sja.org.uk/DIPS-iCalendar";
    say "END:VEVENT";
}

my $input_file = 'Scrape-DIPS.dat';

GetOptions( 'file=s' => \$input_file,
    );

    
my $duties = retrieve($input_file)->{'duties'};

# die Dumper $duties;

# Get lists of members and units (unfortunately don't have members IDs)

my %units;
for my $duty ( @$duties ) {
    next unless $duty->{external_id};
    fixup_dates $duty;
    my $external_id = $duty->{external_id};
    say "Processing duty $external_id";
    for my $d ( @{$duty->{divisions}} ) {
	fixup_dates $d;
	my $u = \%{$units{$d->{division_code}}};
	$u->{name} = $d->{division_name};
	$u->{duties}{$external_id} = $duty;
    }
    # die Dumper $duty;
    for my $m ( @{$duty->{members}} ) {
	# Handly back link in member
	fixup_dates $m;
	$m->{duty} = $duty;
	my $u = \%{$units{$m->{division_code} // '____'}};
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
	for my $m ( sort { $a->{start} cmp $b->{start} } @{$u->{members}{$member_name}{duties}} ) {
	    duty @$m{'duty','start','end'}, "duty-member-shift-$m->{record}";
		# die $division_code;
		csv $division_code,$m->{name},$m->{Role},$m->{duty}{external_id},$m->{duty}{Event},df($m->{start}),df($m->{end});
	}
	end_calendar;
   }
}

my @duties_sorted = sort { $a->{start} cmp $b->{start} } @$duties;

open my $vf, '>', 'vehicles.txt' or die $!;

my %vehicles = (
   FAU => "First Aid Post", # or is it "Treatment Unit"?
   AU => "Ambulance", 
   4x4 => "Off Road Vehicle (4x4)",
   ORA => "Off Road Ambulance",
   CRU=>"Cycle Response Unit",
   MBUS => "Minibus",
   CAR => "Response Car",
   CU=> "Communication Unit",
   SU => "Support Unit",
   xxx => "Treatment Unit", # No requirement code?
   yyy => "Other (not listed)",
);

# Cover status:
#  1 => Still to be confirmed
#  2 => Unit confirms level of cover as requested
#  3 => Unit confirms event with changed level cover
#  4 => Unit cannot cover event
#  8 => Unit is no longer required

for my $duty ( @duties_sorted ) {
   # Consider only duties where vehicles required or assigned
   next unless @{$duty->{assets}} || grep { $duty->{required}{$_} } keys %vehicles;
   say $vf "$duty->{StartDate} $duty->{external_id} $duty->{Event}";
   for my $type ( keys %vehicles ) {
      my $description = $vehicles{$type};
      my $required = $duty->{required}{$type};
      my @assigned =  grep { $_->{Role} eq $description } @{$duty->{assets}};
      my @confirmed = grep { $_->{CoverStatus} eq 2 || $_->{CoverStatus} eq 3 } @{$duty->{divisions}};
      @confirmed = map { { Division => $_->{division_code}, Number => $_->{$type} } } @confirmed;
      @confirmed = grep { $_->{Number} } @confirmed;      
      next unless $required or @assigned or @confirmed;
      print $vf "  $description";
      print $vf " ($required)" if defined $required;
      print $vf ":";
      print $vf " ". join(', ' => map { "$_->{Division}($_->{Number})"} @confirmed) if @confirmed;
      print $vf "\n";
      for ( @assigned ) {
         print $vf "   $_->{CallSign}";
	 if ( @{$_->{Crew} || []} ) { 
            print ": " . join(', ',@{$_->{Crew}})
	 };
	 print "\n";
      }
   }
   say $vf "";
}
