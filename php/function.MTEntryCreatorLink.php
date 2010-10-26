<?php
############################################################################
# Copyright © 2006-2010 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# version 2 for more details. You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.

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
