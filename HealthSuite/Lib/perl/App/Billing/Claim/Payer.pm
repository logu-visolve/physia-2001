##############################################################################
package App::Billing::Claim::Payer;
##############################################################################

use strict;
use App::Billing::Claim::Entity;
use vars qw(@ISA);
use Devel::ChangeLog;
use vars qw(@CHANGELOG);
@ISA = qw(App::Billing::Claim::Entity);

#
#   -- here is the organization's data 
#   -- that is required in a HCFA 1500 or NSF output
#
sub new
{
	my ($type) = shift;
	my $self = new App::Billing::Claim::Entity(@_);
	
	$self->{name} = undef;
	$self->{id} = undef;
	$self->{address} = undef;
	$self->{firstName} = undef;
	$self->{lastName} = undef;
	$self->{middleInitial} = undef;
	$self->{amountPaid} = undef;
	$self->{bcbsPlanCode} = undef;
	$self->{filingIndicator} = undef;
	$self->{sourceOfPayment} = undef;
	$self->{acceptAssignment} = undef;
	$self->{champusSponsorBranch} = undef;
	$self->{champusSponsorGrade} = undef;
	$self->{champusSponsorStatus} = undef;
	
	
	return bless $self, $type;
}

sub property
{
	my ($self, $name, $value) = @_;
	$self->{$name} = $value if defined $value;
	return $self->{$name};
}

sub setChampusSponsorBranch
{
	my ($self, $value) = @_;
	$self->{champusSponsorBranch} = $value;
}

sub getChampusSponsorBranch
{
	my ($self) = @_;
	return $self->{champusSponsorBranch};
}

sub setChampusSponsorGrade
{
	my ($self, $value) = @_;
	$self->{champusSponsorGrade} = $value;
}

sub getChampusSponsorGrade
{
	my ($self) = @_;
	return $self->{champusSponsorGrade};
}
sub setChampusSponsorStatus
{
	my ($self, $value) = @_;
	$self->{champusSponsorStatust} = $value;
}

sub getChampusSponsorStatus
{
	my ($self) = @_;
	return $self->{champusSponsorStatus};
}

sub setAcceptAssignment
{
	my ($self, $treat) = @_;
	my $temp =
		{
			'0' => 'N',
			'NO' => 'N',
			'N' => 'N',
			'1'  => 'Y',
			'YES'  => 'Y',
			'Y'  => 'Y',
			
		};
	$self->{acceptAssignment} = $temp->{uc($treat)};
}

sub getAcceptAssignment
{
	my ($self) = @_;
	
	return $self->{acceptAssignment};
}

sub setSourceOfPayment
{
	my ($self, $value) = @_;
	$self->{sourceOfPayment} = $value;
}

sub getSourceOfPayment
{
	my ($self) = @_;
	
	return $self->{sourceOfPayment};
}

sub setFilingIndicator
{
	my ($self, $treat) = @_;
	$self->{filingIndicator} = $treat;
}

sub getFilingIndicator
{
	my ($self) = @_;
	
	return $self->{filingIndicator};
}

sub getBcbsPlanCode
{
	my $self = shift;
	return $self->{bcbsPlanCode};
}

sub setBcbsPlanCode
{
	my ($self,$value) = @_;
	$self->{bcbsPlanCode} = $value;
}

sub getAmountPaid
{
	my $self = shift;
	return $self->{amountPaid};
}

sub setAmountPaid
{
	my ($self,$value) = @_;
	$self->{amountPaid} = $value;
}

sub getName
{
	my $self = shift;
	return $self->{name};
}

sub getAddress
{
	my $self = shift;
	return $self->{address};
}


sub setName
{
	my ($self,$value) = @_;
	$self->{name} = $value;
}

sub setAddress
{
	my ($self,$value) = @_;
	$self->{address} = $value;
}

sub setId
{
	my ($self,$value) = @_;
	$self->{id} = $value;
}

sub getId
{
	my $self = shift;
	return $self->{id};
}

sub getPayerId
{
	my $self = shift;
	return $self->{id};
}

sub setFirstName
{
	my ($self,$value) = @_;
	
	$self->{firstName} = $value;
}

sub setLastName
{
	my ($self,$value) = @_;
	
	$self->{lastName} = $value;
}

sub setMiddleInitial
{
	my ($self,$value) = @_;
	
	$self->{middleInitial} = $value;
}

sub getFirstName
{
	my ($self) = @_;
	
	return $self->{firstName};
}

sub getLastName
{
	my ($self) = @_;
	
	return $self->{lastName}
}

sub getMiddleInitial
{
	my ($self) = @_;
	
	return $self->{middleInitial};
}

@CHANGELOG =
( 
    # [FLAGS, DATE, ENGINEER, CATEGORY, NOTE]
	[CHANGELOGFLAG_ANYVIEWER | CHANGELOGFLAG_UPDATE, '02/24/2000', 'SSI','Billing Interface/Claim Patient','A new attribute amountpaid is added which will reflect the amount paid by the payer in claim.'],
);


1;
