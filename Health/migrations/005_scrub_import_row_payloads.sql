UPDATE import_row_log
SET raw_payload_json = '{"_redacted":"legacy payload removed during privacy upgrade"}'
WHERE raw_payload_json IS NOT NULL
  AND raw_payload_json <> '{"_redacted":"legacy payload removed during privacy upgrade"}';
