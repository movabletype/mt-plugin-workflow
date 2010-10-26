<?php
function smarty_function_MTEntryCreator($args, &$ctx) {
    $entry = $ctx->stash ('entry');

    $author_id = $entry['entry_created_by'] || $entry['author_id'];
    $author = $ctx->mt->db->fetch_author ($author_id);

    if (isset($args['show_email']))
        $show_email = $args['show_email'];
    else
        $show_email = 0;

    if (isset($args['show_url']))
        $show_url = $args['show_url'];
    else
        $show_url = 1;

    if ($show_url && $author['author_url']) {
        return sprintf("<a href=\"%s\">%s</a>", $author['author_url'], $author['author_name']);
    } elseif ($show_email && $author['author_email']) {
        $str = 'mailto:' . $author['author_email'];
        if (isset($args['spam_protect']) && $args['spam_protect']) {
            $str = spam_protect ($str);
        }
        return sprintf("<a href=\"%s\">%s</a>", $str, $author['author_name']);
    } else {
        return $author['author_name'];
    }
}
