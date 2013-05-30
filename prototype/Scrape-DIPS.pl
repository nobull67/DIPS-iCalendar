use strict;
use warnings;
use WWW::Mechanize::GZip;
use Data::Dumper;
use HTML::TreeBuilder::XPath;
use Storable;
use Getopt::Long;
use 5.10.0;
use warnings FATAL => 'uninitialized';

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;

my %months_to_get = ( 
    forward => 1,
    backward => 0,
    );
my $output_file = 'Scrape-DIPS.dat';

GetOptions( 'user=s' => \my $user,
	    'pass=s' => \my $pass,
	    'months=i' => \$months_to_get{forward},
	    'months-back=i' => \$months_to_get{backward},
	    'start-url=s' => \my $dips,
	    'training' => \my $training,
	    'division=s' => \my @division_filter, # drill down only for these
	    'no-commitment' => \my $no_commitment,
	    'sector' => \my $list_sector,
	    'county' => \my $list_county,
	    'file=s' => \$output_file,
	    'quick-test' => \my $quick_test, # Testing - bail out after one of each thing
    );

die "No user" unless $user;
die "No password" unless $pass;

my $filter = 'myduties'; # Unit level
$filter = 'myarea' if $list_sector;
$filter = '' if $list_county;

$dips //= 'https://dips.sja.org.uk';
$dips .= '/training' if $training;

my $mech = WWW::Mechanize::GZip->new();

$|=1; # So we can print dots

print "Login as $user ";
$mech->get( $dips );
print '.';
$mech->field('UserName',$user);
print '.';
$mech->field('Password',$pass);
print '.';
$mech->submit;	
say '';

say $mech->uri;

($dips = $mech->uri) =~ s/\/index.*//;

say "Root url $dips";

# Avoid start of day redirect later
$mech->get("$dips/DutySystem-List.asp?filter=$filter");

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

my (%duties,%dat,%units_by_name);
$dat{units} = \my %units;

#sub get_unit_info {
#   my $info = shift;
#   unless ( $info->{code} ) {
#        say "Fetch info for $info->{id}";
#	$mech->get("$dips/DivisionManagement-Edit.asp?disptype=edit&division=$info->{id}");
#	($info->{code}) = $mech->content =~ />Unit Reference Code<\/td>(?>.*?<td.*?>\s*)(.*?)</s;
#   }
#   $info;
#}

# Snatch the list of units so we can get the id from the name if we need it
{
  $mech->get("$dips/DivisionPop-upNew.asp?division=NEW");
  my $input = $mech->current_form->find_input( 'DivisionalLink2' );
  my @unit_ids = $input->possible_values;
  my @unit_names = $input->value_names;
  $_->{name} = shift @unit_names for @units{@unit_ids};
  delete @units{ grep { /\D/ } @unit_ids};
  while ( my ($id,$info) = each %units ) {
    $units_by_name{$info->{name}} = $info;
    $info->{id} = $id;
  }
}

{
# Yes, I know we'll fetch home page twice - so shoot me.
    my %month_link_patterns = (
	forward => qr/^Show Next Months/,
	backward => qr/Show Last Months/,
	);
    my %page_link_patterns = (
	forward => qr/^Next Page/,
	backward => qr/<< Last Page/,
	);

    for my $month_direction ( 'forward','backward') {
	if (my $months_to_get = $months_to_get{$month_direction}) {
	    print "Get $months_to_get months duties (filter='$filter' direction=$month_direction)"; 
	    my $page_direction = $month_direction;
	    $mech->get("$dips/DutySystem-List.asp?filter=$filter");

	    {
		my $content = $mech->res->content;
		my ($month) = $content =~
		    /Total Records =.*<b>(?:Duties|Events) Between: \d+\/(\d+)/s or 
		    die $content;

		my ($page_no) = $content =~ /<b>(\d+)<\/b><\/font>/;

		$page_no //= 'none';

		print " $month($page_no)";

		# die $content;
		while ( $content =~ / on[Cc]lick="SE\((\d+)\)\" (?>.*?>)(\S+?)</g ) {
		    $duties{$2}{internal_id}=$1;
		}

		my @links = grep { $_->tag eq 'a' } $mech->links;

		if ( my ($next_page) = grep { $_->text =~ $page_link_patterns{$page_direction} } @links ) {
		    $mech->get($next_page->url);
		    redo;
		}


		last unless --$months_to_get > 0 ;

		# If we've followed 'Last Month' we go to page 1 of last month
		$page_direction = 'forward';

		if ( my ($next_month) = grep { $_->text =~ $month_link_patterns{$month_direction} } @links ) {
		    $mech->get($next_month->url);
		    redo;
		}
	    }
	    say '';
	}
    }
}
# The list of unit duties may not include all those to which members are committed

my $my_division_id;

unless ( $no_commitment ) {
    my %members;

    print "My default division is ";
    $mech->get("$dips/FindMemberCountyWide.asp");
    my $divisional_input= $mech->current_form->find_input('division');
    $my_division_id = $divisional_input->value;
    print "$my_division_id\n";
    undef $my_division_id if $my_division_id eq 'all';
    for my $division_id ( $divisional_input->possible_values ) {
	next unless $division_id =~ /^\d+$/;
	print "Get list of members for $division_id";
	$mech->current_form->value('division',$division_id);
	$mech->current_form->value('area','all');
	$mech->submit;
	$members{$division_id} = \my @m;
	# die Dumper $mech->res->content;
	@m = $mech->res->content =~ /FutureCommitment.aspx?\?disptype=showmember&member=(\d+)'/g; 
	print " - ",scalar(@m),"\n";
	$mech->back;
    }


  DIV: for my $division_id ( keys %members ) {    
      for my $member ( @{$members{$division_id}} ) {
	  print "Future commitment ";
	  $mech->get("$dips/FutureCommitment.asp?disptype=showmember&member=$member");
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

my $duty_count = keys %duties;
say "Found duties = $duty_count";

my $duty_i;

for my $duty ( sort keys %duties ) {
    my $d=$duties{$duty};
    my $internal_id = $d->{internal_id};
	++$duty_i;
    print "$duty_i/$duty_count: $duty";
    unless ( $internal_id ) {
	# If I only external ref then I need to get ref
	# This is insane - we are told to strip the leading zero from the number
	# then the site performs an end-with search on the number!
	# Fortunately the 0-prefixed one should always appear on the first page
	$mech->get("$dips/FindEvent.asp");
	$mech->field('RegionalEvent',$duty);
	$mech->submit;
	my $content = $mech->res->content;
	($internal_id) = $content =~ / on[cC]lick="SE\((\d+)\)" /;
	die $content unless $internal_id;
	$d->{internal_id}=$internal_id;
	print " [$internal_id]"; 
    }
    {
	$mech->get("$dips/DutyInformation2-ShowMap.asp?duty=$internal_id&page=2");
	my $content = $mech->res->content;
	@$d{'external_id','StartDate','StartTime','EndTime'} =
	    $content =~ />(\w+\/\d+\/?\S+) - (\S+) from (\S+) until (\S+)<\/td>/
	    or die $content;
	$mech->form_name('form1'); # Great name eh?
	$d->{$_->name // ''}=$_->value for $mech->current_form->inputs;
	delete $d->{''};
    }

    {
	$mech->get("$dips/DutyInformation8-Show.asp?duty=$internal_id&page=4&pagenumber=0");
	$d->{assets} = \my @c;
	my $content = $mech->res->content;
	#die $content;
	for ($content =~ / on[cC]lick="VS\('(.*?)<\/tr>/sg) {
	   my @a = />([^<>]*)<\/td/g;
	   #die Dumper \@a;
	   for (@a) {
	     s/&nbsp;/ /g;
	     s/^\s+//;
	     s/\s+$//;
	   }
	   # One day may want to add the rest
	   push @c => \my %a;
	   @a{ 'CallSign','Reg','Role'}=@a;
	   $a{crew} = [ grep { $_ } @a[3..6] ];
	}
    }
    
    {
	$mech->get("$dips/DutyInformation4-Show.asp?duty=$internal_id&page=4");
	my $content = $mech->res->content;
	$d->{divisions} = \my @c;
	#die $content;
	while (  $content =~ / on[cC]lick="NW\('(\d+)','(\d+)',[^>]+ title="(.*?) - [^>]+><b>(.*?)<\/b>/g ) {
	    my %i = (
		division_name => $3,
		division_id => $1,
		division_code => $4,
		record => $2, # The ID of this unit at this time on this duty (may be multiple)
	    );
  	    $units{$i{division_id}}{code} //= $i{division_code};
	    next if exclude_division $i{division_code};
	    push @c => \%i;
	    print " $i{division_code}";
	    $mech->get("$dips/DivisionPop-up.asp?division=$i{division_id}&duty=$i{record}");
        # This should not fail, but odly it does
	    if (my $current_form = $mech->current_form) {
		  $i{$_->name // ''}=$_->value for $current_form->inputs;
		}
	    delete @i{'','tempEndTime','tempStartTime','DutyLinkNumber'};
	    #die Dumper \%i;
	}
	$d->{required} = \my %i;
	$mech->get("$dips/DivisionPop-upReq.asp?division=REQ&duty=$internal_id");
	#die $mech->content;
	$i{$_->name // ''}=$_->value for $mech->current_form->inputs;
	delete @i{'','tempEndTime','tempStartTime'};
    }
    say '';
    last if $quick_test;
}

for my $duty ( sort keys %duties ) {
    my $d=$duties{$duty};
    my $internal_id = $d->{internal_id};
    print "Get members on $duty";
    {
	$d->{members} = \my @members;
	$mech->get("$dips/CountMeInService.asp?show=all&duty=$internal_id");
	my $content = $mech->res->content;
	while ( $content =~ / onclick="SM\((\d+)\)" (?>.*?<td>){5}(.*?)</sg ) {
	    my %i = ( 
		record => $1,
	        division_name => $2,
            );
	    # We can only infer the division code if we have seen it before
	    if ( my $division_code = $units_by_name{$i{division_name}}->{code} ) {
	       $i{division_code} = $division_code;
    	       next if exclude_division $division_code;
	    }
  	    push @members => \%i;
	    $mech->get("$dips/CountMeInService.asp?type=editmember&record=$i{record}");
	    ($i{name}) = $mech->res->content =~ /Members Name:<\/b>(?>.*?<td .*?>)(?:&nbsp;)*([^<]*) - /s;
	    $i{$_->name // ''}=$_->value for $mech->current_form->inputs;
	    delete $i{''};
	    # die Dumper \%i; 
	}
    }
    say '';
    last if $quick_test;
}

%dat = (
    %dat, 
    duties=> [ values %duties ],
    my_division_id => $my_division_id,
);

store \%dat, $output_file;

if ( $output_file =~ s/\.dat$/.txt/ ) {
    open my $dump, '>', $output_file or dir $!;
    say $dump Dumper \%dat;
}


__END__
