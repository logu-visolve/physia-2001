###################################################################################
package App::Billing::Output::File::Batch::Claim::Header::NSF3;
###################################################################################

use strict;
use Carp;

sub new
{
	my ($type,%params) = @_;
	
	return \%params,$type;
}

sub numToStr
{
	my($self,$len,$lenDec,$tarString) = @_;
	my @temp1 = split(/\./,$tarString); 
	$temp1[0]=substr($temp1[0],0,$len);
	$temp1[1]=substr($temp1[1],0,$lenDec);
	
	my $fg =  "0" x ($len - length($temp1[0])).$temp1[0]."0" x ($lenDec - length($temp1[1])).$temp1[1];
	return $fg; 
}


sub recordType
{
	'CB0';
}

sub formatData
{
	my ($self, $container, $flags, $inpClaim) = @_;
	my $spaces = ' ';
	my $claimLegalRepresentator = $inpClaim->{legalRepresentator};
	my $claimLegalRepresentatorAddress = $claimLegalRepresentator->{address};
	
	return sprintf("%-3s%-2s%-17s%-20s%-10s%-2s%1s%-18s%-12s%-18s%-12s%-15s%-5s%-2s%-9s%-10s%-82s%-82s",
	$self->recordType(),
	$spaces,	# Reserved Filler
	substr($inpClaim->{careReceiver}->getAccountNo(), 0, 17), # Patient Control Number
	substr($claimLegalRepresentator->getLastName ,0,20),    # Last name
	substr($claimLegalRepresentator->getFirstName ,0,12),	# First Name
	$spaces, 	# Filler of Responsible First Name
	substr($claimLegalRepresentator->getMiddleInitial ,0,1),	# Middle Initial
	substr($claimLegalRepresentatorAddress->getAddress1 ,0,18),	# Address 1
	$spaces,	# Address1 Filler
	substr($claimLegalRepresentatorAddress->getAddress2 ,0,18),	# Address 2
	$spaces,	# Address 2 Filler
	substr($claimLegalRepresentatorAddress->getCity ,0,15), 	# City
	$spaces,	# City Filler
	substr($claimLegalRepresentatorAddress->getState() ,0,2),	# State
	substr($claimLegalRepresentatorAddress->getZipCode() ,0,9),	# ZipCode
	$spaces,	# Responsible Party Telephone Number
	$spaces,	# Filler National
	$spaces		# Filler Local
	);
}

1;
