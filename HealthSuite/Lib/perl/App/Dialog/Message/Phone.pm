##############################################################################
package App::Dialog::Message::Phone;
##############################################################################

use strict;
use CGI::Validator::Field;
use CGI::Dialog;
use App::Dialog::Message;
use base qw(App::Dialog::Message);

use CGI::Carp qw(fatalsToBrowser);

use vars qw(%RESOURCE_MAP);
%RESOURCE_MAP = (
	'phone_message' => {
			_arl => ['message_id', 'doc_spec_subtype'],
			_modes => ['send', 'trash', 'read', 'forward', 'reply_to', 'reply_to_all',],
			_idSynonym => 'message_' . App::Universal::MSGSUBTYPE_PHONE_MESSAGE,
		},
);


sub new
{
	my $self = App::Dialog::Message::new(@_);
	
	$self->{id} = 'phone_message';
	$self->{heading} = '$Command Phone Message';
	
	return $self;
}


sub addExtraFields
{
	my $self = shift;
	
	return;
	
	my @fields = (
		new CGI::Dialog::Field(
			name => 'return_phone',
			caption => 'Return Phone #',
			type => 'phone',
		),
	);
	
	return @fields;
}


sub makeStateChanges
{
	my ($self, $page, $command, $activeExecMode, $dlgFlags) = @_;

	$self->SUPER::makeStateChanges($page, $command, $activeExecMode, $dlgFlags);
	$self->setFieldFlags('patient_id', FLDFLAG_REQUIRED);	
}


sub populateData
{
	my $self = shift;
	my ($page, $command, $activeExecMode, $flags) = @_;
	
	$self->SUPER::populateData(@_);
	return unless $flags & CGI::Dialog::DLGFLAG_DATAENTRY_INITIAL;
	
	my $existingMsg = $self->{existing_message};
	
	if ($command eq 'send')
	{
		# We're creating an entirely new message
	}
	elsif (grep {$_ eq $command} ('trash', 'read'))
	{
		# We're displaying an existing message
		$page->field('return_phone', $existingMsg->{'return_phone'}) if defined $existingMsg->{'return_phone'};
	}
	elsif (grep {$_ eq $command} ('reply_to', 'reply_to_all', 'forward'))
	{
		$page->field('return_phone', $existingMsg->{'return_phone'}) if defined $existingMsg->{'return_phone'};
	}
}


sub execute
{
	my $self = shift;
	my ($page, $command, $flags, $messageData) = @_;
	$messageData = {} unless defined $messageData;
	
	$messageData->{'returnPhone'} = $page->field('return_phone');
	return $self->SUPER::execute($page, $command, $flags, $messageData);
}


sub saveMessage
{
	my $self = shift;
	my $page = shift;
	my $messageData = shift;
	my %schemaActionData = @_;
	
	$schemaActionData{doc_spec_subtype} = App::Universal::MSGSUBTYPE_PHONE_MESSAGE;
	return $self->SUPER::saveMessage($page, $messageData, %schemaActionData);
}


sub saveRegardingPatient
{
	my $self = shift;
	my $page = shift;
	my $messageData = shift;
	my %schemaActionData = @_;

	if (my $phone = $messageData->{'returnPhone'})
	{
		$schemaActionData{'value_textB'} = $phone;
	}
	
	return $self->SUPER::saveRegardingPatient($page, $messageData, %schemaActionData);
}


1;
