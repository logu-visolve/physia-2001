###################################################################################
package App::Billing::Output::File::Batch::Claim::Record::NSF::THIN_GC0;
###################################################################################


use strict;
use Carp;

# for exporting NSF Constants
use App::Billing::Universal;


use vars qw(@ISA);
@ISA = qw(App::Billing::Output::File::Batch::Claim::Record::NSF);

sub recordType
{
	'GC0';
}

sub formatData
{
	my ($self, $container, $flags, $inpClaim, $payerType) = @_;
	
	return "";
}

1;

###################################################################################
package App::Billing::Output::File::Batch::Claim::Record::NSF::THIN_GDat;
###################################################################################


use strict;
use Carp;

use vars qw(@ISA);
@ISA = qw(App::Billing::Output::File::Batch::Claim::Record::NSF);

sub recordType
{
	'GDat';
}

sub formatData
{
	my ($self, $container, $flags, $inpClaim) = @_;
	
	return "";
}

1;