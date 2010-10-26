var fr_new_row_i = 0;

Node.prototype.swapNode = function(node) {
    var nextSibling = this.nextSibling;
    var parentNode = this.parentNode;
    parentNode.replaceChild(this, node);
    parentNode.insertBefore(node, nextSibling);  
}

Array.prototype.swap = function(a, b) {
    var tmp = this[a];
    this[a] = this[b];
    this[b] = tmp;
}

function moveRow(dir, row_name) {
    frMoveRow('workflow_step-listing-table', dir, row_name, wf_step_list);
}

function frMoveRow(table_id, dir, row_name, item_list) {
    var table = getByID(table_id);
    var order_field = getByID(row_name + '_order');
    var order = parseInt(order_field.value);
    var i = order - 1;
    var swap_row;
    var swap_i;
    if (dir == 'up') {
        if (i == 0) {
            return true;
        }
        swap_i = i - 1;
        swap_row = table.tBodies[0].rows[swap_i];
        table.tBodies[0].rows[i].swapNode(swap_row);
    }
    if (dir == 'down') {
        if (i == (item_list.length - 1)) {
            return true;
        }
        swap_i = i + 1;
        swap_row = table.tBodies[0].rows[swap_i];
        swap_row.swapNode(table.tBodies[0].rows[i]);
    }
    var swap_order_field = getByID(item_list[swap_i] + '_order');
    item_list.swap(i, swap_i);
    order_field.value = swap_i + 1;
    swap_order_field.value = i + 1;
    frReFlipFlop(table);
}

function frReFlipFlop(table) {
    for (var i = 1; i < table.tBodies[0].rows.length; i++) {
        table.tBodies[0].rows[i].className = (i % 2) ? 'odd' : 'even';
    }
}
