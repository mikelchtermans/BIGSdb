/**
 * Written by Keith Jolley 
 * Copyright (c) 2021, University of Oxford 
 * E-mail: keith.jolley@zoo.ox.ac.uk
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

var currentRequest = null;
const MOBILE_WIDTH = 480;

$(function() {
	showOrHideElements();
	setElementWidths(grid);
	$("select#add_field,label[for='add_field']").css("display", "inline");
	var layout = $("#layout").val();
	var fill_gaps = $("#fill_gaps").prop('checked');
	var grid;
	try {
		grid = new Muuri('.grid', {
			dragEnabled: true,
			layout: {
				alignRight: layout.includes('right'),
				alignBottom: layout.includes('bottom'),
				fillGaps: fill_gaps
			},
			dragStartPredicate: function(item, e) {
				return enable_drag;
			}
		}).on('move', function() {
			saveLayout(grid);
		});
		if (order) {
			loadLayout(grid, order);
		}
	} catch (err) {
		console.log(err.message);
	}


	$("#panel_trigger,#close_trigger").click(function() {
		$("#modify_panel").toggle("slide", { direction: "right" }, "fast");
		$("#panel_trigger").show();
		return false;
	});
	$("#panel_trigger").show();
	$(document).mouseup(function(e) {
		var container = $("#modify_panel");

		// if the target of the click isn't the container nor a
		// descendant of the container
		if (!container.is(e.target) && container.has(e.target).length === 0) {
			container.hide();
		}
	});
	$("#layout").change(function() {
		layout = $("#layout").val();
		try {
			grid._settings.layout.alignRight = layout.includes('right');
			grid._settings.layout.alignBottom = layout.includes('bottom');
			grid.layout();
		} catch (err) {
			// Grid is empty.
		}
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=layout&value=" + layout);
	});
	$("#fill_gaps").change(function() {
		fill_gaps = $("#fill_gaps").prop('checked');
		try {
			grid._settings.layout.fillGaps = fill_gaps;
			grid.layout();
		} catch (err) {
			// Grid is empty.
		}
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=fill_gaps&value=" + (fill_gaps ? 1 : 0));
	});
	$("#enable_drag").change(function() {
		enable_drag = $("#enable_drag").prop('checked');
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=enable_drag&value=" + (enable_drag ? 1 : 0));

	});
	$("#edit_elements").change(function() {
		var edit_elements = $("#edit_elements").prop('checked');
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=edit_elements&value=" + (edit_elements ? 1 : 0));
		$("span.dashboard_edit_element").css("display", edit_elements ? "inline" : "none");
	});
	$("#remove_elements").change(function() {
		var remove_elements = $("#remove_elements").prop('checked');
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=remove_elements&value=" + (remove_elements ? 1 : 0));
		$("span.dashboard_remove_element").css("display", remove_elements ? "inline" : "none");
	});
	$("#include_old_versions").change(function() {
		var include_old_versions = $("#include_old_versions").prop('checked');
		$.ajax({
			url: url + "&page=dashboard&updatePrefs=1&attribute=include_old_versions&value=" +
				(include_old_versions ? 1 : 0)
		}).done(function() {
			reloadAllElements(grid);
		});
	});


	$("#add_element").click(function() {
		var nextId = getNextid();
		addElement(grid, nextId);
	});

	$("div#dashboard").on("click touchstart", ".dashboard_edit_element", function() {
		var id = $(this).attr('data-id');
		editElement(grid, id);
	});
	$("div#dashboard").on("click touchstart", ".dashboard_remove_element", function() {
		var id = $(this).attr('data-id');
		removeElement(grid, id);
	});
	$("div#dashboard").on("click touchstart", ".setup_element", function() {
		var id = $(this).attr('data-id');
		editElement(grid, id);
	});
	$("div#dashboard").on("click touchstart", ".dashboard_explore_element", function() {
		var id = $(this).attr('data-id');
		if (elements[id]['url']) {
			var explore_url = elements[id]['url'];
			var params = {};
			if (elements[id]['post_data']) {
				params = elements[id]['post_data'];
			}
			params['sent'] = 1;
			if (explore_url.includes('&page=query') && $("#include_old_versions").prop('checked')) {
				params['include_old'] = 'on';
			}
			post(elements[id]['url'], params);
		}
	});
	applyFormatting();

	var dimension = ['width', 'height'];
	dimension.forEach((value) => {
		$(document).on("change", '.' + value + '_select', function(event) {
			var id = $(this).attr('id');
			var element_id = id.replace("_" + value, "");
			changeElementDimension(grid, element_id, value);
		});
	});
	$(document).on("change", '.element_option', function(event) {
		var id = $(this).attr('id');
		var attribute = id.replace(/^\d+_/, "");
		var element_id = id.replace("_" + attribute, "");
		var value;
		if (attribute == 'hide_mobile') {
			value = $(this).prop('checked');
			if (value) {
				$("div#element_" + element_id + " div.item-content").addClass("hide_mobile");
			} else {
				$("div#element_" + element_id + " div.item-content").removeClass("hide_mobile");
			}
		} else {
			value = $(this).val();
		}
		changeElementAttribute(grid, element_id, attribute, value);
	});
	$(document).on("change", '.palette_selector', function(event) {
		var id = $(this).attr('id');
		id = id.replace(/_palette$/, "");
		show_palette(id);
	});
	$('.multi_menu_trigger').on('click', function() {
		var trigger_id = this.id;
		var panel_id = trigger_id.replace('_trigger', '_panel');
		if ($("#" + panel_id).css('display') == 'none') {
			$("#" + panel_id).slideDown();
			$("#" + trigger_id).html('<span class="fas fa-minus"></span>');
		} else {
			$("#" + panel_id).slideUp();
			$("#" + trigger_id).html('<span class="fas fa-plus"></span>');
		}
	});
	$('a#dashboard_toggle').on('click', function() {
		$.get(url + "&page=dashboard&updatePrefs=1&attribute=default&value=0", function() {
			window.location = url;
		});
	});
	$(window).resize(function() {
		setElementWidths();
		showOrHideElements();
		loadNewElements();
	});

});

function setElementWidths() {
	var dashboard_width = $("div#dashboard").width();
	var margin = 5;
	var gutter = (dashboard_width - (margin * 2)) % 150;
	var extra = gutter / 10;
	var w1 = 150;
	var w2 = 304;
	var w3 = 458;
	var w4 = 612;
	$("div.dashboard_element_width1").css("width", w1 + extra);
	$("div.dashboard_element_width2").css("width", w2 + extra * 2);
	$("div.dashboard_element_width3").css("width", w3 + extra * 3);
	$("div.dashboard_element_width4").css("width", w4 + extra * 4);
	//Special case to ensure full mobile width is filled with a count element.
	if (dashboard_width < w3 - (margin * 2)) {
		$("div.dashboard_element_width2").css("width", w3);
	}
}


function showOrHideElements() {
	var small_screen = $("div#dashboard").width() < MOBILE_WIDTH;
	$("div.hide_mobile").css("display", small_screen ? "none" : "block");
	$.each(elements, function(index, element) {
		if (element['display'] == 'setup') {
			$("div#element_" + element['id'] + " div.item-content").css("display", "block");
		}
	});
}


//Post to the provided URL with the specified parameters.
//https://stackoverflow.com/questions/133925/javascript-post-request-like-a-form-submit/5533477#5533477
function post(path, parameters) {
	var form = $('<form></form>');

	form.attr("method", "post");
	form.attr("action", path);

	$.each(parameters, function(key, value) {
		var field = $('<input></input>');
		field.attr("type", "hidden");
		field.attr("name", key);
		field.attr("value", value);
		form.append(field);
	});

	// The form needs to be a part of the document in
	// order for us to be able to submit it.
	$(document.body).append(form);
	form.submit();
}

function clean_value(value) {
	if (value == null) {
		return;
	}
	if (Array.isArray(value)) {
		value = value.map(function(el) {
			return el.trim();
		});
		value = value.filter(function(el) {
			return el != null && el != '';
		});
	} else {
		value = value.trim();
	}
	return value;
}

function changeElementAttribute(grid, id, attribute, value) {
	if (elements[id][attribute] === value) {
		return;
	}
	if (attribute === 'specific_values' && !Array.isArray(value)) {
		if (value.includes("\n")) {
			value = value.split("\n");
		} else {
			value = value.split();
		}
	}

	if (value == true || value == false) {
		value = value ? 1 : 0;
	} else {
		value = clean_value(value);
	}
	elements[id][attribute] = value;
	saveAndReloadElement(grid, id);
}

function applyFormatting() {
	fitty(".dashboard_big_number", {
		maxSize: 64,
		observeMutations: false
	});
	$(".item-content div.subtitle a").tooltip();
}

function getNextid() {
	if (Object.keys(elements).length === 0) {
		return 1;
	}
	var max = Math.max(...Object.keys(elements));
	return max + 1;
}

function addElement(grid, id) {
	if (Object.keys(elements).length === 0) {
		$("div#empty").html("");
	}
	var add_url = url + "&page=dashboard&new=" + id;
	var field = $("#add_field").val();
	if (field) {
		add_url += "&field=" + field;
	}

	$.get(add_url, function(json) {
		try {
			var div = document.createRange().createContextualFragment(JSON.parse(json).html);
			// Element may already exist if add button was clicked multiple
			// times before AJAX response was received.
			if (!(id in elements)) {
				grid.add([div.firstChild]);
				elements[id] = JSON.parse(json).element;
				saveElements(grid);
			}
			applyFormatting();
		} catch (err) {
			console.log(err.message);
		}
	});
}

function editElement(grid, id, setup) {
	$("span#control_" + id).hide();
	$("span#wait_" + id).show();
	$.get(url + "&page=dashboard&control=" + id, function(html) {
		$(html).appendTo('body').modal();
		if ($("#edit_elements").prop("checked")) {
			$("span#control_" + id).show();
		}
		$("span#wait_" + id).hide();
		showOrHideControlElements(id);

		$("select.watermark_selector").fontIconPicker({
			theme: 'fip-darkgrey',
			emptyIconValue: 'none',
		});
		$("div.modal").on("change", "#" + id + "_visualisation_type", function() {
			showOrHideControlElements(id);
			checkAndShowVisualisation(grid, id);
		});
		$("div.modal").on("change", "#" + id + "_breakdown_display,#" +
			id + "_specific_value_display,#" +
			id + "_specific_values,#" +
			id + "_bar_colour_type", function() {
				showOrHideControlElements(id);
				checkAndShowVisualisation(grid, id);
			});
		$("div.modal").on($.modal.AFTER_CLOSE, function(event, modal) {
			$("div.modal").remove();
		});
	});
}

function showOrHideControlElements(id) {
	var visualisation_type = $("input[name='" + id + "_visualisation_type']:checked").val();
	var specific_value_display = $("#" + id + "_specific_value_display").val();
	var breakdown_display = $("#" + id + "_breakdown_display").val();

	//Hide all elements initially.
	$("fieldset#change_duration_control,fieldset#design_control,"
		+ "li#value_selector,li#breakdown_display_selector,li#specific_value_display_selector,"
		+ "li#top_value_selector,li#watermark_control,li#palette_control,li#text_colour_control,"
		+ "li#background_colour_control,li.gauge_colour,li#bar_colour_type,li#chart_colour").css("display", "none");

	//Enable elements as required.
	if (elements[id]['display'] == 'record_count') {
		$("fieldset#change_duration_control,fieldset#design_control").css("display", "inline");
		$("li#text_colour_control,li#background_colour_control,li#watermark_control").css("display", "block");
	}

	else if (visualisation_type === 'specific values') {
		$("li#specific_value_display_selector,li#value_selector").css("display", "block");
		if (specific_value_display === 'gauge') {
			$("fieldset#design_control").css("display", "inline");
			$("li.gauge_colour").css("display", "block");
		} else if (specific_value_display === 'number') {
			$("fieldset#change_duration_control,fieldset#design_control").css("display", "inline");
			$("li#watermark_control,li#text_colour_control,li#background_colour_control").css("display", "block");
		}
	} else if (visualisation_type === 'breakdown') {
		$("li#breakdown_display_selector").css("display", "block");
		if (breakdown_display === 'bar') {
			$("fieldset#design_control,li#bar_colour_type").css("display", "inline");
			var bar_colour_type = $("input[name='" + id + "_bar_colour_type']:checked").val();
			if (bar_colour_type === "continuous") {
				$("li#chart_colour").css("display", "block");
			}
		} else if (breakdown_display === 'cumulative') {
			$("fieldset#design_control").css("display", "inline");
			$("li#chart_colour").css("display", "block");
		} else if (breakdown_display === 'map') {
			$("fieldset#design_control").css("display", "inline");
			$("li#palette_control").css("display", "block");
			show_palette(id);
		} else if (breakdown_display === 'top') {
			$("li#top_value_selector").css("display", "block");
		}
	}
}

function show_palette(id) {
	var palettes = {
		blue: colorbrewer.Blues[5],
		green: colorbrewer.Greens[5],
		purple: colorbrewer.Purples[5],
		orange: colorbrewer.Oranges[5],
		red: colorbrewer.Reds[5],
		'blue/green': colorbrewer.BuGn[5],
		'blue/purple': colorbrewer.BuPu[5],
		'green/blue': colorbrewer.GnBu[5],
		'orange/red': colorbrewer.OrRd[5],
		'purple/blue': colorbrewer.PuBu[5],
		'purple/blue/green': colorbrewer.PuBuGn[5],
		'purple/red': colorbrewer.PuRd[5],
		'red/purple': colorbrewer.RdPu[5],
		'yellow/green': colorbrewer.YlGn[5],
		'yellow/green/blue': colorbrewer.YlGnBu[5],
		'yellow/orange/brown': colorbrewer.YlOrBr[5],
		'yellow/orange/red': colorbrewer.YlOrRd[5]
	};
	var selected = $("#" + id + "_palette").val();
	for (var i = 0; i < 5; i++) {
		$("#palette_" + i).css("background", palettes[selected][i]);
	}

}

function checkAndShowVisualisation(grid, id) {
	var visualisation_type = $("input[name='" + id + "_visualisation_type']:checked").val();
	var breakdown_display = $("#" + id + "_breakdown_display").val();
	var specific_value_display = $("#" + id + "_specific_value_display").val();
	var specific_values = $("#" + id + "_specific_values").val();
	if (visualisation_type === 'specific values') {
		if (specific_value_display != '0' && specific_values.length != 0) {
			elements[id]['display'] = 'field';
			elements[id]['url'] = url + "&page=query";
			elements[id]['url_text'] = 'Query records';
			elements[id]['post_data'] = {
				db: instance,
				page: "query",
				attribute: elements[id]['field'],
				list: Array.isArray(specific_values) ? specific_values.join("\n") : specific_values
			}
			saveAndReloadElement(grid, id);
		} else {
			changeElementAttribute(grid, id, 'display', 'setup');
		}
	} else if (visualisation_type === 'breakdown') {
		if (breakdown_display != 0) {
			elements[id]['display'] = 'field';
			saveAndReloadElement(grid, id);
		} else {
			changeElementAttribute(grid, id, 'display', 'setup');
		}
	}
}

function reloadElement(grid, id) {
	$.get(url + "&page=dashboard&element=" + id, function(json) {
		try {
			$("div#element_" + id + "> .item-content > .ajax_content").html(JSON.parse(json).html);
			elements[id] = JSON.parse(json).element;
			applyFormatting();
		} catch (err) {
			console.log(err.message);
		}
	});
}

function reloadAllElements(grid) {
	$.each(Object.keys(elements), function(index, value) {
		reloadElement(grid, value);
	});
}

function loadNewElements(grid) {
	$.each(Object.keys(elements), function(index, value) {
		if (!loadedElements[value] && !($("div#dashboard").width() < MOBILE_WIDTH && elements[value]['hide_mobile'])) {
			reloadElement(grid, value);
			loadedElements[value] = 1;
		}
	});
}

function removeElement(grid, id) {
	var item = grid.getItem($("div#element_" + id)[0]);
	grid.remove([item], { removeElements: true });
	delete elements[id];
	saveElements(grid);
	if (Object.keys(elements).length == 0) {
		$("div#empty").html(empty);
	}
}

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
	elements[id][attribute] = Number(new_dimension);
	setElementWidths();
	saveAndReloadElement(grid, id);
	grid.refreshItems().layout();
}

function saveElements(grid) {
	$.post(url, {
		db: instance,
		page: "dashboard",
		updatePrefs: 1,
		attribute: "elements",
		value: JSON.stringify(elements)
	});
	saveLayout(grid);
}

function saveAndReloadElement(grid, id) {
	currentRequest = $.ajax({
		url: url,
		type: 'POST',
		data: {
			db: instance,
			page: "dashboard",
			updatePrefs: 1,
			attribute: "elements",
			value: JSON.stringify(elements)
		},
		beforeSend: function() {
			if (currentRequest != null) {
				currentRequest.abort();
			}
		},
		success: function() {
			reloadElement(grid, id);
		}
	});
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
		layout: 'instant'
	});
}

function saveLayout(grid) {
	var layout = serializeLayout(grid);
	$.post(url, {
		db: instance,
		page: "dashboard",
		updatePrefs: 1,
		attribute: "order",
		value: layout
	});
}

function resetDefaults() {
	$("#modify_panel").toggle("slide", { direction: "right" }, "fast");
	$.get(url + "&resetDefaults=1", function() {
		$("#layout").val("left-top");
		$("#fill_gaps").prop("checked", true);
		$("#enable_drag").prop("checked", false);
		$("#edit_elements").prop("checked", false);
		$("#remove_elements").prop("checked", false);
		location.reload();
	});
}

function commify(x) {
	return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
