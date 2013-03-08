If you don't volunteer for St John Ambulance in the UK then this is probably no interest to you.

St John Ambulance in the UK have a web-based database system to manage first aid provision at public events.

Most people aged 16-50 in the 21st century developed world (including most UK SJA volunteers) have electronic diaries that can import iCalendar files.

This is a first cut at getting my SJA duty commitments out of DIPS and into my Google Calendar. So far it just does what I need but I've put it on GitHub in case any other computer nerds in SJA want to hack on it. At least this way we can hope to avoid uncontrolled divergence.

It consists of two simple command line Perl scripts so if you've no idea what a "Command line" is you'll probably need help to use them.

To use this program you first need to install the Perl programming language. If you are using Windows then I suggest Strawberry Perl. http://strawberryperl.com/

Once you've installed Perl you'll need a couple of Perl modules. So long as you have a direct (not proxied) web connection you should be able to install these by typing "CPAN" then the module name at the command prompt.

cpan WWW::Mechanize
cpan WWW::Mechanize::GZip
cpan HTML::TreeBuilder::XPath
cpan Getopt::Long

Once you've got Perl and the modules installed you should download the two scripts from the prototype directory into a directory on your computer and then in that directory run the two programs (with your DIPS credentials).

Scrape-DIPS.pl --user=XXXXXX --pass=XXXXX
Dump-iCalendar.pl

The first program visits DIPS reading all your unit's duties and creates a file (in the current directory) Scrape-DIPS.dat which is just a big serialised Perl hash. (If you need to go through a web proxy to access DIPS then you need a Perl nerd to show you how to configure proxies in Perl).

By "your unit" I mean the unit that comes up as the default when you select "Divisional listing".

By "your unit's duties" I mean any duty that appears in your "Divisional listing" for the six calendar months starting with the current month. (You can adjust this window with --months= and months-back=).

You can also opt to scrape the entire the county or sector listing instead using --county and --sector options 

Unless you say --no-commitment then it'll also include any duties in the future commitment listing of all the members you can see through "Find members".
This is most useful if a Unit-level user, otherwise it'll probably be just like grabbing everything.

The second program processes Scrape-DIPS.dat and creates iCalendar files for every division and menber which you can import into your Google Calendar or other diary program.  Note that some of these may be incomplete if you didn't scrape the whole county.

So far very little of the information from Scrape-DIPS.dat ends up in iCalendar, just the title, location and times of each duty.

Future possible enhancements include the inclusion of which of your members are at the duty (and when) in the event description.

I'm also considering the ability to generate a separate iCalendar file for each member with event times start/end set to their shift times and the overall duty times (if different) in the event summary.

I should tidy up what happens to users who get to see multiple units in "Find members". Unfortunately with only a level-2 account myself and the training system so sparsely populated this would be rather hard to test.

The scraping program should be able to dump all duties at the area (sector) or county level and go back into the past.

I need to look at if I can somehow alter the colours of the events in Google Calendars based on the type of event.  

Maybe the intermediate data file should be an SQL database. Then again maybe not.
