use strict;
use warnings;
use WWW::Mechanize;
use Data::Dumper;
use HTML::TreeBuilder::XPath;
use Storable;
use Getopt::Long;
use 5.10.0;

my $months_forward = 1;
my $months_back = 0;
my $output_file = 'Scrape-DIPS.dat';

GetOptions( 'user=s' => \my $user,
	    'pass=s' => \my $pass,
	    'months=i' => \$months_forward,
	    'months-back=i' => \$months_back,
	    'training' => \my $training,
	    'division=s' => \my @division_filter, # drill down only for these
	    'no-commitment' => \my $no_commitment,
	    'sector' => \my $list_sector,
	    'county' => \my $list_county,
	    'file=s' => \$output_file,
	    'quick-test' => \my $quick_test, # Testing - bail out after one of each thing
    );

my $filter = 'myduties'; # Unit level
$filter = 'myarea' if $list_sector;
$filter = '' if $list_county;

my $dips='https://secure.duties.org.uk';
$dips .= '/training' if $training;

my $mech = WWW::Mechanize->new();

$|=1; # So we can print dots

print "Login as $user";
$mech->get( $dips );
$mech->field('UserName',$user);
$mech->field('Password',$pass);
$mech->submit;
say '';

my (%duties);

# Avoid start of day redirect later
$mech->get("$dips/newsja/DutySystem-List.asp?filter=$filter");

sub exclude_division {
    my $division_code = shift // ''; # We find some users w/o unit
    !!@division_filter &&
	! grep { $_ eq $division_code } @division_filter;
}

sub trim {
    for (shift) {
	s/^\s+//;
	s/\s+$//;
	return $_;
    }
}

sub get_duty_list {
    my ($months_to_get,$next_link_pattern) = @_;
    if ($months_to_get) {
	print "Get $months_to_get months duties (filter='$filter' link=$next_link_pattern)"; 

	$mech->get("$dips/newsja/DutySystem-List.asp?filter=$filter");

	my $months_got;
	{
	    print ".";
	    my $content = $mech->res->content;
	    while ( $content =~ /&duty=(\d+)&[^>]*><font size="2">(\S+?)</g ) {
		$duties{$2}{internal_id}=$1;
	    }

	    my @links = grep { $_->tag eq 'a' } $mech->links;

	    if ( my ($next_page) = grep { $_->text =~ /^Next Page/ } @links ) {
		$mech->get($next_page->url);
		redo;
	    }
	    last unless ++$months_got < $months_to_get;
	    if ( my ($next_month) = grep { $_->text =~ $next_link_pattern } @links ) {
		$mech->get($next_month->url);
		redo;
	    }
	}
	say '';
    }
}

get_duty_list $months_forward, qr/^Show Next Months/;
# Yes, I know we'll fetch this month twice - so shoot me.
get_duty_list $months_back, qr/Show Last Months/;

# The list of unit duties may not include all those to which members are committed

my $my_division_id;

unless ( $no_commitment ) {
    my %members;

    print "My default division is ";
    $mech->get("$dips/newsja/FindMemberCountyWide.asp");
    my $divisional_input= $mech->current_form->find_input('division');
    $my_division_id = $divisional_input->value;
    print "$my_division_id\n";
    undef $my_division_id if $my_division_id eq 'all';
    for my $division_id ( $divisional_input->possible_values ) {
	next unless $division_id =~ /^\d+$/;
	print "Get list of members for $division_id";
	$mech->current_form->value('division',$division_id);
	$mech->submit;
	$members{$division_id} = \my @m;
	@m = $mech->res->content =~ /FutureCommitment.asp\?disptype=showmember&member=(\d+)'/g; 
	print " - ",scalar(@m),"\n";
	$mech->back;
    }


  DIV: for my $division_id ( keys %members ) {    
      for my $member ( @{$members{$division_id}} ) {
	  print "Future commitment ";
	  $mech->get("$dips/newsja/FutureCommitment.asp?disptype=showmember&member=$member");
	  my $content = $mech->res->content;
	  if ( $content =~ /NO records to show - Please go back and search again/ ) {
	      print "[$member] - none\n";
	      next;
	  }
	  # say $content;
	  my $tree = HTML::TreeBuilder::XPath->new_from_content($content);
	  my $name = $tree->findvalue('/html/body/table/tr[1]/td[2]');
	  my @rows = $tree->findnodes('/html/body/table/tr[td[6] and not(@bgcolor)]');
	  for my $row ( @rows ) {
	      my $duty = $row->findvalue('td[1]');
	      my ($from,$until) = $row->findvalue('td[3]') =~ /(\d+:\d+)/g;
	      push @{$duties{$duty}{members_committed}} => {
		  id => $member,
		  name => $name,
		  from => $from,
		  until => $until,
		  division_id => $division_id,
	      };
	  }
	  print "$name - ",scalar(@rows),"\n";
	  last DIV if $quick_test;
      }
  }
}

say "Found duties = ",scalar(keys(%duties));

for my $duty ( sort keys %duties ) {
    my $d=$duties{$duty};
    my $internal_id = $d->{internal_id};
    print "Get details of $duty";
    unless ( $internal_id ) {
	# If I only external ref then I need to get ref
	# This is insane - we are told to strip the leading zero from the number
	# then the site performs an end-with search on the number!
	# Fortunately the 0-prefixed one should always appear on the first page
	my ($year,$number) = $duty =~ /^(\d+)\/0*(\d+)$/ or die;
	$mech->get("$dips/newsja/FindEvent.asp");
	$mech->field('Year',$year);
	$mech->field('Duty',$number);
	$mech->field('StartDate',"01/01/$year");
	$mech->field('EndDate',"31/12/$year");
	$mech->submit;
	my $content = $mech->res->content;
	($internal_id) = $content =~ /.*&duty=(\d+)&.*>$duty<.*/;
	die $content unless $internal_id;
	$d->{internal_id}=$internal_id;
	print " [$internal_id]"; 
    }
    {
	$mech->get("$dips/newsja/DutyInformation2-ShowMap.asp?duty=$internal_id&page=2");
	my $content = $mech->res->content;
	@$d{'external_id','StartDate','StartTime','EndTime'} =
	    $content =~ />(\w+\/\d+\/\d+) - (\S+) from (\S+) until (\S+)<\/td>/
	    or die $content;
	$mech->form_name('form1'); # Great name eh?
	$d->{$_->name // ''}=$_->value for $mech->current_form->inputs;
	delete $d->{''};
}

    {
	$mech->get("$dips/newsja/DutyInformation4-Show.asp?duty=$internal_id&page=4");
	my $content = $mech->res->content;
	$d->{divisions} = \my @c;
	while (  $content =~ /w\('(DivisionPop-up(Req)?\.asp\?division=(\w+).*?)'.*?<b>(\w+)/g ) {
	    my $division_code = $4;
	    my $url = $1; 
	    my $is_req_row = !!$2;
	    my %i = $is_req_row ? () : (
		division_id => $3,
		division_code => $division_code,
		);
	    if ( $is_req_row ) {
		$d->{required} = \%i;
	    } else {
		next if exclude_division $division_code;
		push @c => \%i;
	    }
	    print " $division_code";
	    $url =~ s/&amp;/&/g; # Wierd escaping in the javascript
	    $mech->get($url);
	    $i{$_->name // ''}=$_->value for $mech->current_form->inputs;
	    delete $i{''};
	    unless ( $is_req_row ) {
		my $tree = HTML::TreeBuilder::XPath->
		    new_from_content($mech->res->content);
		($i{division_name})=
		    $tree->findnodes_as_strings('/html/body/form/table/tr[2]/td[2]');
	    }
	}
    }
    {
	$d->{members} = \my @members;
	$mech->get("$dips/newsja/CountMeInService.asp?duty=$internal_id");
	my $tree = HTML::TreeBuilder::XPath->new_from_content($mech->res->content);
	my @rows = $tree->findnodes('/html/body/table/tr/td/center/table[2]/tr');
	for my $row ( @rows ) {
	    # We want the record ID of the members attendance at the 
	    # duty to make the UID for the iCalendar entry in the
	    # member's calendar as member could have more than on
	    # shift on a duty
	    
	    next unless my ($url,$record) = ( $row->attr('onclick') // '')
		=~ /'(.*type=editmember&record=(\d+).*?)'/ ;

	    my @c = $row->findnodes_as_strings('td');
	    my ( $division_code,$division_name) = $c[4] =~ /\(\w+\)\s*(\w+)\s+-\s+(.*)/;
	    next if exclude_division $division_code;
	    print ".";
	    my $name=trim("@c[0,1]");
	    # Let's assume there's noboby called "- Lead Name"
	    my $lead = 0+ $name =~ s/\s+- Lead Name\s*$//i;
	    my ($role) = $c[2] =~ /\((\w+)\)/;
	    # Need to drill down to to get start and end as
	    # we can't assume the date of the shift is the same
	    # as the date of the duty
	    $mech->get($url);
	    my %i = ( 
		record => $record,
		name => $name, 
		division_name => $division_name,
		division_code => $division_code,
		);
	    push @members => \%i;
	    $i{$_->name // ''}=$_->value for $mech->current_form->inputs;
	    delete $i{''};
	}
	say '';
    }
    last if $quick_test;
}

store { 
    duties=> [ values %duties ],
    my_division_id => $my_division_id,
}, $output_file;

__END__
