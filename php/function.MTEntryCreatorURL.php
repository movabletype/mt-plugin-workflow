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
    return $author['author_url'];
}
