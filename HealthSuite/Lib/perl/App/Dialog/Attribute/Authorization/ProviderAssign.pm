##############################################################################
package App::Dialog::Attribute::Authorization::ProviderAssign;
##############################################################################

use DBI::StatementManager;
use App::Statements::Person;

use strict;
use Carp;
use CGI::Dialog;
use CGI::Validator::Field;
use App::Dialog::Field::Attribute;
use App::Dialog::Attribute::Authorization;
use App::Universal;
use Date::Manip;
use Devel::ChangeLog;
use vars qw(@ISA @CHANGELOG);
@ISA = qw(App::Dialog::Attribute::Authorization);

sub initialize
{
	my $self = shift;

	$self->heading('$Command Provider Assignment Indicator');

	$self->addContent(
				new App::Dialog::Field::Attribute::Name(
						caption => 'Provider Assignment',
						name => 'value_textb',
						fKeyStmtMgr => $STMTMGR_PERSON,
						fKeyStmt => 'selProviderAssign',	
						#type => 'foreignKey',						
						#fKeyTable => 'auth_assign',
						#fKeySelCols => "abbrev, caption",
						fKeyDisplayCol => 1,
						fKeyValueCol => 0,
						attrNameFmt => 'Provider Assignment',
						valueType => $self->{valueType},
						selAttrNameStmtName => 'selAttributeByItemNameAndValueTypeAndParent'),

	);

	$self->SUPER::initialize();
}

use constant PANEDIALOG_AUTHORIZATION => 'Dialog/Authorization/Provider Assignment';

@CHANGELOG =
(
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '02/03/2000', 'MAF',
		PANEDIALOG_AUTHORIZATION,
		'Created new dialog for Provider Assignment.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '03/14/2000', 'RK',
		PANEDIALOG_AUTHORIZATION,
		'Removed Item Path from Item Name'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '03/17/2000', 'RK',
		PANEDIALOG_AUTHORIZATION,
		'Replaced fkeyxxx select in the dialog with Sql statement from Statement Manager.'],
);

1;