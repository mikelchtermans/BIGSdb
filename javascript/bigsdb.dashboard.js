/**
 * Written by Keith Jolley Copyright (c) 2021, University of Oxford E-mail:
 * keith.jolley@zoo.ox.ac.uk
 * 
 * This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
 * 
 * BIGSdb is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version.
 * 
 * BIGSdb is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with
 * BIGSdb. If not, see <http://www.gnu.org/licenses/>.
 */


$(function () {
	var layout = $("#layout").val();
	var fill_gaps = $("#fill_gaps").prop('checked');
	var grid;
	try {
		grid = new Muuri('.grid',{
	
		dragEnabled: true,
		layout: {
			alignRight : layout.includes('right'),
			alignBottom : layout.includes('bottom'),
			fillGaps: fill_gaps
		}		
	}).on('move', function () {
    	saveLayout(grid);
	});
		if (order){
			loadLayout(grid, order);
		}
	} catch(err) {
		console.log(err.message);
	}
	
	$("#panel_trigger,#close_trigger").click(function(){		
		$("#modify_panel").toggle("slide",{direction:"right"},"fast");
		$("#panel_trigger").show();		
		return false;
	});
	$("#panel_trigger").show();
	$("#layout").change(function(){
		layout = $("#layout").val();
		try {
		grid._settings.layout.alignRight = layout.includes('right');
		grid._settings.layout.alignBottom = layout.includes('bottom');		
		grid.layout();
		} catch(err){
			// Grid is empty.
		}
		$.ajax(ajax_url + "&attribute=layout&value=" + layout );	
	});
	$("#fill_gaps").change(function(){
		fill_gaps = $("#fill_gaps").prop('checked');
		try {
			grid._settings.layout.fillGaps = fill_gaps;		
			grid.layout();		
		} catch(err){
			// Grid is empty.
		}
		$.ajax(ajax_url + "&attribute=fill_gaps&value=" + (fill_gaps ? 1 : 0) );	
	});
	$("#edit_elements").change(function(){	
		var edit_elements = $("#edit_elements").prop('checked');
		$.ajax(ajax_url + "&attribute=edit_elements&value=" + (edit_elements ? 1 : 0) );
		$("span.dashboard_edit_element").css("display",edit_elements ? "inline" : "none");
	});
	$("#remove_elements").change(function(){	
		var remove_elements = $("#remove_elements").prop('checked');
		$.ajax(ajax_url + "&attribute=remove_elements&value=" + (remove_elements ? 1 : 0) );
		$("span.dashboard_remove_element").css("display",remove_elements ? "inline" : "none");
	});
	$(".dashboard_edit_element").click(function(){
		var id=$(this).attr('data-id');
		$("span#control_" + id).hide();
		$("span#wait_" + id).show();
		$.get(modal_control_url + "&control=" + id, function(html) {
			$(html).appendTo('body').modal();
			$("span#control_" + id).show();
			$("span#wait_" + id).hide();
		});
	});
	$(".dashboard_remove_element").click(function(){
		var id=$(this).attr('data-id');
		var item = grid.getItem($("div#element_" + id)[0]);
		grid.remove([item],{ removeElements: true });
		delete elements[id];
		saveElements(grid);
		if (Object.keys(elements).length == 0){	
			$("div#dashboard").html(empty);
		}
	});

	var dimension = ['width','height'];
	dimension.forEach((value) => {
		$(document).on("change", '.' + value + '_select', function(event) { 
			var id = $(this).attr('id');
			var element_id = id.replace("_" + value,"");
			changeElementDimension(grid, element_id, value);
		});
	});
	$('a#dashboard_toggle').on('click', function(){
		$.get(ajax_url + "&attribute=default&value=0",function(){
			window.location=url + "?db=" + instance;	
		});	
	});	
});

function changeElementDimension(grid, id, attribute) {
	var item_content = $("div.item[data-id='" + id + "'] > div.item-content");
	var classes = item_content.attr('class');
	var class_list = classes.split(/\s+/);
	$.each(class_list, function(index, value) {
		if (value.includes('dashboard_element_' + attribute)) {
			item_content.removeClass(value);
		}
	});
	var new_dimension = $("input[name='" + id + "_" + attribute + "']:checked")
			.val();
	item_content.addClass("dashboard_element_" + attribute + new_dimension);
	$("span#" + id + "_" + attribute).html(new_dimension);
	elements[id][attribute] = Number(new_dimension);
	$.post(ajax_url,{
    	db:instance,
    	page:"dashboard",
    	updatePrefs:1,
    	attribute:"elements",
    	value:JSON.stringify(elements)
    });
	grid.refreshItems().layout();
}

function saveElements(grid){
	$.post(ajax_url,{
    	db:instance,
    	page:"dashboard",
    	updatePrefs:1,
    	attribute:"elements",
    	value:JSON.stringify(elements)
    });
	saveLayout(grid);
}

function serializeLayout(grid) {
	var itemIds = grid.getItems().map(function(item) {
		return item.getElement().getAttribute('data-id');
	});
	return JSON.stringify(itemIds);
}

function loadLayout(grid, serializedLayout) {
	var layout = JSON.parse(serializedLayout);
	var currentItems = grid.getItems();
	var currentItemIds = currentItems.map(function(item) {
		return item.getElement().getAttribute('data-id')
	});
	var newItems = [];
	var itemId;
	var itemIndex;

	for (var i = 0; i < layout.length; i++) {
		itemId = layout[i];
		itemIndex = currentItemIds.indexOf(itemId);
		if (itemIndex > -1) {
			newItems.push(currentItems[itemIndex])
		}
	}
	grid.sort(newItems, {
		layout : 'instant'
	});
}

function saveLayout(grid) {
    var layout = serializeLayout(grid);
    $.post(url,{
    	db:instance,
    	page:"dashboard",
    	updatePrefs:1,
    	attribute:"order",
    	value:layout
    });
}

function resetDefaults(){
	$("#modify_panel").toggle("slide",{direction:"right"},"fast");
	$.get(reset_url, function() {		
		$("#layout").val("left-top");
		$("#fill_gaps").prop("checked",true);
		$("#edit_elements").prop("checked",false);
		$("#remove_elements").prop("checked",false);
		location.reload();
	});
}
