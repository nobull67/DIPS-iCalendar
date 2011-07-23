use strict;
use warnings;
use WWW::Mechanize;
use Data::Dumper;
use HTML::TreeBuilder::XPath;
use Storable;
use Getopt::Long;
use 5.10.0;

my $months_to_get = 6;
my $output_file = 'Scrape-DIPS.dat';

GetOptions( 'user=s' => \my $user,
	    'pass=s' => \my $pass,
	    'months=i' => \$months_to_get,
	    'file=s' => \$output_file,
    );

my $filter = 'myduties'; # 'myduties' for Unit level and '' for whole county


my $quick_test = 0;

my $dips='https://secure.duties.org.uk';
my $mech = WWW::Mechanize->new();

$mech->get( $dips );
$mech->field('UserName',$user);
$mech->field('Password',$pass);
$mech->submit;

my (%member_names,%duties);

$|=1; # So we can print dots

# Avoid start of day redirect later
$mech->get("$dips/newsja/DutySystem-List.asp?filter=$filter");

if ($months_to_get) {
    last if $quick_test;
    print "Get $months_to_get months duties for unit"; 

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
	if ( my ($next_month) = grep { $_->text =~ /^Show Next Months/ } @links ) {
	    $mech->get($next_month->url);
	    redo;
	}
    }
    print " - ". scalar(keys(%duties)) . "\n";
}

# The list of unit duties may not include all those to which members are committed

my $my_division_id;

my @members = do {
    print "My division id is ";
    $mech->get("$dips/newsja/FindMemberCountyWide.asp");
    $my_division_id = $mech->current_form->value('division');
    print "$my_division_id\n";
    print "Get list of members";
    $mech->submit;
    $mech->res->content =~ /FutureCommitment.asp\?disptype=showmember&member=(\d+)'/g;
};
print " - ",scalar(@members),"\n";

for my $member ( @members ) {
    print "Future commitment ";
    $mech->get("$dips/newsja/FutureCommitment.asp?disptype=showmember&member=$member");
    my $content = $mech->res->content;
    if ( $content =~ /NO records to show - Please go back and search again/ ) {
	print "[$member] - none\n";
	next;
    }
    # say $content;
    my $tree = HTML::TreeBuilder::XPath->new_from_content($content);
    my @member_duties = $tree->findnodes_as_strings('/html/body/table/tr[td[6] and not(@bgcolor)]/td[1]');
    my $name = $tree->findvalue('/html/body/table/tr[1]/td[2]');
    push @{$duties{$_}{members}} => { id => $member, name => $name } for @member_duties;
    print "$name - ",scalar(@member_duties),"\n";
    last if $quick_test;
}

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
	@$d{'external_id','date','from','until'} =
	    $content =~ />(\w+\/\d+\/\d+) - (\S+) from (\S+) until (\S+)<\/td>/;
	$mech->form_name('form1'); # Great name eh?
	$d->{$_->name}=$_->value for $mech->current_form->inputs;
	print " $d->{date}";
    }

    {
	$mech->get("$dips/newsja/DutyInformation4-Show.asp?duty=$internal_id&page=4");
	my $content = $mech->res->content;
	my @c;
	while (  $content =~ /w\('(DivisionPop-up(?:Req)?\.asp\?division=(\w+).*?)'.*?<b>(\w+)/g ) {
	    print " $3";
	    my $url = $1; 
	    my %i = (
		division_id => $2,
		division_code => $3,
		);
	    push @c => \%i;
	    $url =~ s/&amp;/&/g; # Wierd escaping in the javascript
	    $mech->get($url);
	    $i{$_->name // ''}=$_->value for $mech->current_form->inputs;
	    delete $i{''};
	    my $tree = HTML::TreeBuilder::XPath->new_from_content($mech->res->content);
	    ($i{division_name})=$tree->findnodes_as_strings('/html/body/form/table/tr[2]/td[2]');

	}
	$d->{divisions} = \@c;
	$d->{required} = my $r = shift @c;
	die unless delete $r->{division_id} eq 'REQ'; # Sanity check
	delete $r->{division_name}; delete $r->{division_code};
	print "\n";
    }
    last if $quick_test;
}

store { duties=> [ values %duties ] }, $output_file;
 
__END__
