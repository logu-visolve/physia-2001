##############################################################################
package App::Component::WorkList::Collection;
##############################################################################

use strict;
use CGI::Layout;
use CGI::Component;

use Date::Calc qw(:all);
use Date::Manip;
use DBI::StatementManager;
use App::Statements::Component::Scheduling;
use App::Statements::Person;
use App::Statements::Scheduling;
use App::Schedule::Utilities;
use Data::Publish;
use Exporter;
use App::Statements::Worklist::WorklistCollection;

use vars qw(@ISA %RESOURCE_MAP );
@ISA   = qw(CGI::Component Exporter);

%RESOURCE_MAP = (
	'worklist-collection' => {
		_class => new App::Component::WorkList::Collection(),
		},
	);

sub initialize
{
	my ($self, $page) = @_;
	my $layoutDefn = $self->{layoutDefn};
	my $arlPrefix = '/worklist/collection';

	$layoutDefn->{frame}->{heading} = "Work List";
	$layoutDefn->{style} = 'panel';
	
}

sub getHtml
{
	my ($self, $page) = @_;

	$self->initialize($page);
	createLayout_html($page, $self->{flags}, $self->{layoutDefn}, $self->getComponentHtml($page));
}

sub getComponentHtml
{
	my ($self, $page) = @_;
	
	my $selectedDate = $page->param('_seldate') || 'today';
	$selectedDate = 'today' unless ParseDate($selectedDate);
	my $fmtDate = UnixDate($selectedDate, '%m/%d/%Y');

	my $facility_id = $page->session('org_id');
	my $user_id = $page->session('user_id');
	
	my ($time1, $time2);
	
	if ($page->session('showTimeSelect'))
	{
		$time1 = $page->session('time1') || '12:00am';
		$time2 = $page->session('time2') || '11:59pm';
	}
	else
	{
		$time1 = $page->session('time1') || 30;
		$time2 = $page->session('time2') || 120;
	}

	my @start_Date = Decode_Date_US($fmtDate);
	my @end_Date   = Add_Delta_Days (@start_Date, 1);
	my $startDate = sprintf("%02d/%02d/%04d", $start_Date[1],$start_Date[2],$start_Date[0]);
	my $endDate   = sprintf("%02d/%02d/%04d", $end_Date[1],$end_Date[2],$end_Date[0]);
	
	my $startTime = $startDate . " $time1";
	my $endTime   = $startDate . " $time2";

	my @data = ();
	my $html;# = qq{
		#<style>
		#	a.today {text-decoration:none; font-family:Verdana; font-size:8pt}
		#	strong {font-family:Tahoma; font-size:8pt; font-weight:normal}
		#</style>
		#};
	my $pub =
	{
		columnDefn =>
			[
				{colIdx => 0, head => 'Patient ID', hAlign=> 'left',dAlign => 'left',dataFmt=>"<A HREF = '/person/#0#/profile'>#0#</A>",},
				{colIdx => 1, head => 'Event Description', dAlign => 'center'},							
				{colIdx => 2, head => 'Balance' ,dAlign => 'center',dformat => 'currency', url=>'/person/#0#/account'},
				{colIdx => 3, head => 'Age', dAlign => 'center'},
				{colIdx => 4, head => 'Next Appt', dAlign => 'center'},			
				{colIdx => 5, head => 'Reck Date', dAlign => 'center'},			
				{colIdx => 6, head => "Actions", dAlign => 'center'},			
			
		],
	};	


	my $person = $STMTMGR_WORKLIST_COLLECTION ->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selPerCollByIdDate',$page->session('user_id'),$startDate);
	
	foreach (@$person)
	{
		
		next if $_->{trans_subtype} ne 'Owner';
		#MARK RECORD AS ACCOUNT CONTACT FOR $page->session('user_id');
		#my $upd = $STMTMGR_		
		my $appt= $STMTMGR_WORKLIST_COLLECTION ->getSingleValue($page, 
			STMTMGRFLAG_NONE, 'selNextApptById', $_->{person_id},$startDate);
		
			
		my $reck = $STMTMGR_WORKLIST_COLLECTION ->getRowAsHash($page, 
			STMTMGRFLAG_NONE, 'selReckDateById', $_->{person_id},$page->session('user_id'));
		
		my $account = $STMTMGR_WORKLIST_COLLECTION ->getRowAsHash($page,STMTMGRFLAG_NONE, 'selAccBalAgeById',$startDate,$_->{person_id}); 
		$account->{age}="N/A" if $account->{age} <0;
		$STMTMGR_WORKLIST_COLLECTION->execute($page,STMTMGRFLAG_NONE,'insAccountOwner',$_->{person_id},$page->session('user_id'),$page->session('org_id')) if ! defined $_->{trans_subtype}; 				
		
		my @rowData = (							
			$_->{person_id},
			'Self-Pay',						
			$account->{balance},
			$account->{age},
			$appt,
			$reck->{trans_begin_stamp},
			qq{<nobr>
				<A HREF="/worklist/collection/dlg-add-account-notes/$_->{person_id}"
					TITLE='Add Account Notes'>
					<IMG SRC='/resources/icons/coll-account-notes.gif' BORDER=0></A>
				<A HREF="/worklist/collection/dlg-add-transfer-account/$_->{person_id}/$_->{trans_id}"
					TITLE='Transfer Patient Account'>
					<IMG SRC='/resources/icons/coll-transfer-account.gif' BORDER=0></A>
				<A HREF="/worklist/collection/dlg-add-reck-date/$_->{person_id}/$reck->{trans_id}"
					TITLE='Add Reck Date'>
					<IMG SRC='/resources/icons/coll-reck-date.gif' BORDER=0></A>
				<A HREF="/worklist/collection/dlg-add-close-account/$_->{person_id}/$_->{trans_id}"
					TITLE='Close Account'>
					<IMG SRC='/resources/icons/coll-close-account.gif' BORDER=0></A>
			</nobr>}, 


		);

		push(@data, \@rowData);
	}

	$html .= createHtmlFromData($page, 0, \@data,$pub);

	$html .= "<i style='color=red'>No Collection data found.  Please setup Resource and Facility selections.</i> <P>" 
		if (scalar @{$person} < 1);

	return $html;
}

sub formatStamp
{
	my ($stamp) = @_;

	if ($stamp =~ /\d\d\/\d\d\/\d\d\d\d/)
	{
		my ($day, $time) = split(/\s/, $stamp);
		return qq{$day $time};
	}
	else
	{
		return "<b>$stamp</b>";
	}

}


1;
