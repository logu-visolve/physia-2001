package Apache::HealthSuite::PracticeManagement;

use strict;
use Apache;
use Apache::Constants qw(:common);
use CGI qw(:standard);
use App::ResourceDirectory;

sub handler
{
	my $r = shift;
	my $DEBUG = ref($r) && $r->dir_config("StatINCDebug") ? 1 : 0;

	eval {
		my $arl;
		$arl = $1 if $ENV{REQUEST_URI} =~ /^\/?(.*)$/;
		$arl = "search" unless $arl;
		App::ResourceDirectory::handleARL($arl);
		return OK;
	};

	if ($@ && $DEBUG)
	{
		$r->content_type('text/html');
    	$r->send_http_header();
    	$r->print("<h1>Perl Runtime Errors:</h1><font color=red>$@</font>");
	}
}

1;

