##############################################################################
package App::Statements::Document;
##############################################################################

use strict;
use Exporter;
use DBI::StatementManager;
use App::Universal;

use vars qw(@ISA @EXPORT $STMTMGR_DOCUMENT);
@ISA    = qw(Exporter DBI::StatementManager);
@EXPORT = qw($STMTMGR_DOCUMENT);

$STMTMGR_DOCUMENT = new App::Statements::Document(
	'selMessage' => qq{
		SELECT
			Document.doc_id as message_id,
			Document.doc_orig_stamp AS send_on,
			Document.doc_recv_stamp AS read_on,
			Document.doc_source_id AS from_id,
			Document.doc_name AS subject,
			Document.doc_content_small AS message,
			attr_repatient.value_text AS repatient_id,
			attr_repatient.value_int AS deliver_records,
			attr_repatient.value_textB AS return_phone,
			repatient.simple_name AS repatient_name
		FROM
			Document,
			Document_Attribute attr_repatient,
			Person repatient
		WHERE
			(
				Document.doc_id = attr_repatient.parent_id (+) AND
				attr_repatient.value_type (+) = @{[App::Universal::ATTRTYPE_PATIENT_ID]} AND
				attr_repatient.item_name (+) = 'Regarding Patient' AND
				attr_repatient.value_text = repatient.person_id (+)
			) AND
			Document.doc_id = :1
	},
	'selMessageToList' => qq{
		SELECT
			value_text AS to_person_id
		FROM
			Document_Attribute
		WHERE
			parent_id = :1 AND
			value_type = @{[App::Universal::ATTRTYPE_PERSON_ID]} AND
			item_name = 'To'
	},
	'selMessageCCList' => qq{
		SELECT
			value_text AS cc_person_id
		FROM
			Document_Attribute
		WHERE
			parent_id = :1 AND
			value_type = @{[App::Universal::ATTRTYPE_PERSON_ID]} AND
			item_name = 'CC'
	},
	'selMessageNotes' => qq{
		SELECT
			TO_CHAR(cr_stamp, 'IYYYMMDDHH24MISS') as when,
			person_id AS person_id,
			value_text AS notes,
			value_int AS private
		FROM
			Document_Attribute
		WHERE
			parent_id = :1 AND
			value_type = @{[App::Universal::ATTRTYPE_TEXT]} AND
			item_name = 'Notes' AND
			(value_int = 0 OR person_id = :2)
	},
	'selMessageRecipientAttrId' => qq{
		SELECT
			item_id
		FROM
			Document_Attribute
		WHERE
			parent_id = :1 AND
			value_type = @{[App::Universal::ATTRTYPE_PERSON_ID]} AND
			item_name IN ('To', 'CC') AND
			value_text = :2
	},
);

1;