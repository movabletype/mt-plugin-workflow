<?php
function smarty_function_MTEntryCreator($args, &$ctx) {
  $entry = $ctx->stash ('entry');

  $author_id = $entry['entry_created_by'] || $entry['author_id'];
  $author = $ctx->mt->db->fetch_author ($author_id);
  return $author['author_nickname'];
}
?>
