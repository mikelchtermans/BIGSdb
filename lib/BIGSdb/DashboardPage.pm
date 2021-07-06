#Written by Keith Jolley
#Copyright (c) 2021, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::DashboardPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::IndexPage);
use BIGSdb::Constants qw(:design :interface);
use Try::Tiny;
use JSON;
use Data::Dumper;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant LAYOUT_TEST => 0;    #TODO Remove

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('updatePrefs') ) {
		$self->_update_prefs;
		return;
	}
	if ( $q->param('control') ) {
		$self->_ajax_controls( scalar $q->param('control') );
		return;
	}
	if ( $q->param('setup') ) {
		$self->_ajax_controls( scalar $q->param('setup'), { setup => 1 } );
		return;
	}
	if ( $q->param('new') ) {
		$self->_ajax_new( scalar $q->param('new') );
		return;
	}
	if ( $q->param('element') ) {
		$self->_ajax_get( scalar $q->param('element') );
		return;
	}
	my $desc = $self->get_db_description( { formatted => 1 } );
	my $max_width = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $title_max_width = $max_width - 15;
	say q(<div class="flex_container" style="flex-direction:column;align-items:center">);
	say q(<div>);
	say qq(<div style="width:95vw;max-width:${title_max_width}px"></div>);
	say qq(<div id="title_container" style="max-width:${title_max_width}px">);
	say qq(<h1>$desc database</h1>);
	$self->print_general_announcement;
	$self->print_banner;

	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		$self->print_set_section;
	}
	say q(</div>);
	say qq(<div id="main_container" class="flex_container" style="max-width:${max_width}px">);
	say qq(<div class="index_panel" style="max-width:${max_width}px">);
	$self->_print_main_section;
	say q(</div>);
	say q(</div>);
	say q(</div>);
	say q(</div>);
	$self->_print_modify_dashboard_fieldset;
	return;
}

sub _ajax_controls {
	my ( $self, $id, $options ) = @_;
	my $elements = $self->_get_elements;
	my $q        = $self->{'cgi'};
	say q(<div class="modal">);
	say $options->{'setup'} ? q(<h2>Setup visual element</h2>) : q(<h2>Modify visual element</h2>);
	say qq(<p>Field: $elements->{$id}->{'name'}</p>);
	$self->_get_size_controls( $id, $elements->{$id} );
	say q(</div>);
	return;
}

sub _get_size_controls {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset><legend>Size</legend>);
	say q(<ul><li><span class="fas fa-arrows-alt-h fa-fw"></span> );
	say $q->radio_group(
		-name    => "${id}_width",
		-id      => "${id}_width",
		-class   => 'width_select',
		-values  => [ 1, 2, 3, 4 ],
		-default => $element->{'width'}
	);
	say q(</li><li><span class="fas fa-arrows-alt-v fa-fw"></span> );
	say $q->radio_group(
		-name    => "${id}_height",
		-id      => "${id}_height",
		-class   => 'height_select',
		-values  => [ 1, 2, 3 ],
		-default => $element->{'height'}
	);
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub _ajax_new {
	my ( $self, $id ) = @_;
	my $element = {
		id     => $id,
		order  => $id,
		width  => 1,
		height => 1,
	};
	if (LAYOUT_TEST) {
		$element->{'name'}    = "Test element $id";
		$element->{'display'} = 'test';
	} else {
		my $default_elements = {
			sp_count => {
				name          => ucfirst("$self->{'system'}->{'labelfield'} count"),
				display       => 'record_count',
				show_increase => 'week'
			}
		};
		my $q     = $self->{'cgi'};
		my $field = $q->param('field');
		if ( $default_elements->{$field} ) {
			$element = { %$element, %{ $default_elements->{$field} } };
		} else {
			( my $display_field = $field ) =~ s/^[f]_//x;
			$element->{'name'}    = $display_field;
			$element->{'field'}   = $field;
			$element->{'display'} = 'setup';
		}
	}
	say encode_json(
		{
			element => $element,
			html    => $self->_get_element_html($element)
		}
	);
	return;
}

sub _ajax_get {
	my ( $self, $id ) = @_;
	my $elements = $self->_get_elements;
	if ( $elements->{$id} ) {
		say encode_json(
			{
				element => $elements->{$id},
				html    => $self->_get_element_content( $elements->{$id} )
			}
		);
		return;
	}
	say encode_json(
		{
			html => '<p>Invalid element!</p>'
		}
	);
	return;
}

sub _get_dashboard_empty_message {
	my ($self) = @_;
	return q(<p><span class="dashboard_empty_message">Dashboard contains no elements!</span></p>)
	  . q(<p>Go to dashboard settings to add visualisations.</p>);
}

sub _print_main_section {
	my ($self) = @_;
	my $elements = $self->_get_elements;
	say q(<div style="min-height:400px"><div id="empty">);
	if ( !keys %$elements ) {
		say $self->_get_dashboard_empty_message;
	}
	say q(</div>);
	say q(<div id="dashboard" class="grid">);
	my %display_immediately = map { $_ => 1 } qw(test setup record_count);
	my $ajax_load = [];
	foreach my $element ( sort { $elements->{$a}->{'order'} <=> $elements->{$b}->{'order'} } keys %$elements ) {
		my $display = $elements->{$element}->{'display'};
		if ( $display_immediately{$display} ) {
			say $self->_get_element_html( $elements->{$element} );
		} else {
			say $self->_load_element_html_by_ajax( $elements->{$element} );
			push @$ajax_load, $element;
		}
	}
	say q(</div></div>);
	if (@$ajax_load) {
		$self->_print_ajax_load_code($ajax_load);
	}
	return;
}

sub _print_ajax_load_code {
	my ( $self, $element_ids ) = @_;
	local $" = q(,);
	say q[<script>];
	say q[$(function () {];
	foreach my $element_id (@$element_ids) {
		say << "JS"
	var element_ids = [@$element_ids];
	\$.each(element_ids, function(index,value){
		\$.ajax({
	    	url:"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=dashboard&element=" + value
	    }).done(function(json){
	       	try {
	       	    \$("div#element_" + value + " > .item-content > .ajax_content").html(JSON.parse(json).html);
	       	} catch (err) {
	       		console.log(err.message);
	       	} 	          	    
	    });			
	});    
JS
	}
	say q[});];
	say q(</script>);
	return;
}

sub _get_elements {
	my ($self) = @_;
	my $elements = {};
	if ( defined $self->{'prefs'}->{'dashboard.elements'} ) {
		eval { $elements = decode_json( $self->{'prefs'}->{'dashboard.elements'} ); };
		if (@$) {
			$logger->error('Invalid JSON in dashboard.elements.');
		}
		return $elements;
	}
	if (LAYOUT_TEST) {
		return $self->_get_test_elements;
	}
	return $elements;
}

sub _get_test_elements {
	my ($self) = @_;
	my $elements = {};
	for my $i ( 1 .. 10 ) {
		my $w = $i % 2 ? 1 : 2;
		$w = 3 if $i == 7;
		$w = 4 if $i == 4;
		my $h = $i == 2 ? 2 : 1;
		$elements->{$i} = {
			id      => $i,
			order   => $i,
			name    => "Test element $i",
			width   => $w,
			height  => $h,
			display => 'test',
		};
	}
	return $elements;
}

sub _get_element_html {
	my ( $self, $element ) = @_;
	my $buffer       = qq(<div id="element_$element->{'id'}" data-id="$element->{'id'}" class="item">);
	my $width_class  = "dashboard_element_width$element->{'width'}";
	my $height_class = "dashboard_element_height$element->{'height'}";
	$buffer .= qq(<div class="item-content $width_class $height_class">);
	$buffer .= $self->_get_element_controls( $element->{'id'} );
	$buffer .= $self->_get_element_content($element);
	$buffer .= q(</div></div>);
	return $buffer;
}

sub _load_element_html_by_ajax {
	my ( $self, $element ) = @_;
	my $buffer       = qq(<div id="element_$element->{'id'}" data-id="$element->{'id'}" class="item">);
	my $width_class  = "dashboard_element_width$element->{'width'}";
	my $height_class = "dashboard_element_height$element->{'height'}";
	$buffer .= qq(<div class="item-content $width_class $height_class">);
	$buffer .= $self->_get_element_controls( $element->{'id'} );
	$buffer .= q(<div class="ajax_content"><span class="dashboard_wait_ajax fas fa-sync-alt fa-spin"></span></div>);
	$buffer .= q(</div></div>);
	return $buffer;
}

sub _get_element_content {
	my ( $self, $element ) = @_;
	my %display = (
		test         => sub { $self->_get_test_element_content($element) },
		setup        => sub { $self->_get_setup_element_content($element) },
		record_count => sub { $self->_get_record_count_element_content($element) }
	);
	if ( $display{ $element->{'display'} } ) {
		return $display{ $element->{'display'} }->();
	}
	return q();
}

sub _get_test_element_content {
	my ( $self, $element ) = @_;
	my $buffer =
	    qq(<p style="font-size:3em;padding-top:0.75em;color:#aaa">$element->{'id'}</p>)
	  . q(<p style="text-align:center;font-size:0.9em;margin-top:-2em">)
	  . qq(W<span id="$element->{'id'}_width">$element->{'width'}</span>; )
	  . qq(H<span id="$element->{'id'}_height">$element->{'height'}</span></p>);
	return $buffer;
}

sub _get_setup_element_content {
	my ( $self, $element ) = @_;
	my $buffer = q(<div><p style="font-size:2em;padding-top:0.75em;color:#aaa">Setup</p>);
	$buffer .= q(<p style="font-size:0.8em;overflow:hidden;text-overflow:ellipsis;margin-top:-1em">)
	  . qq($element->{'name'}</p>);
	$buffer .= qq(<p><span data-id="$element->{'id'}" class="setup_element fas fa-wrench"></span></p>);
	$buffer .= q(</div>);
	return $buffer;
}

sub _get_record_count_element_content {
	my ( $self, $element ) = @_;
	my $buffer     = qq(<div class="title">$element->{'name'}</div>);
	my $count      = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
	my $nice_count = BIGSdb::Utils::commify($count);
	$buffer .= qq(<p style="margin:1em"><span class="dashboard_big_number">$nice_count</span></p>);
	if ( $element->{'show_increase'} && $count > 0 ) {
		my %allowed = map { $_ => 1 } qw(week month year);
		if ( $allowed{ $element->{'show_increase'} } ) {
			my $past_count = $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM $self->{'system'}->{'view'} "
				  . "WHERE date_entered <= now()-interval '1 $element->{'show_increase'}'" );
			if ($past_count) {
				my $increase      = $count - $past_count;
				my $nice_increase = BIGSdb::Utils::commify($increase);
				my $class         = $increase ? 'increase' : 'no_change';
				$buffer .= qq(<p class="dashboard_comment $class"><span class="fas fa-caret-up"></span> )
				  . qq($nice_increase [$element->{'show_increase'}]</p>);
			}
		}
	}
	return $buffer;
}

sub _get_element_controls {
	my ( $self, $id ) = @_;
	my $display = $self->{'prefs'}->{'dashboard.remove_elements'} ? 'inline' : 'none';
	my $buffer =
	    qq(<span data-id="$id" id="remove_$id" )
	  . qq(class="dashboard_remove_element far fa-trash-alt" style="display:$display"></span>)
	  . qq(<span data-id="$id" id="wait_$id" class="dashboard_wait fas fa-sync-alt )
	  . q(fa-spin" style="display:none"></span>);
	$display = $self->{'prefs'}->{'dashboard.edit_elements'} ? 'inline' : 'none';
	$buffer .=
	    qq(<span data-id="$id" id="control_$id" class="dashboard_edit_element fas fa-sliders-h" )
	  . qq(style="display:$display"></span>);
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache muuri modal fitty bigsdb.dashboard);
	$self->choose_set;
	$self->{'breadcrumbs'} = [];
	if ( $self->{'system'}->{'webroot'} ) {
		push @{ $self->{'breadcrumbs'} },
		  {
			label => $self->{'system'}->{'webroot_label'} // 'Organism',
			href => $self->{'system'}->{'webroot'}
		  };
	}
	push @{ $self->{'breadcrumbs'} },
	  { label => $self->{'system'}->{'formatted_description'} // $self->{'system'}->{'description'} };
	my $q = $self->{'cgi'};
	foreach my $ajax_param (qw(updatePrefs control resetDefaults new setup element)) {
		if ( $q->param($ajax_param) ) {
			$self->{'type'} = 'no_header';
			last;
		}
	}
	my $guid = $self->get_guid;
	if ( $q->param('resetDefaults') ) {
		$self->{'prefstore'}->delete_dashboard_settings( $guid, $self->{'system'}->{'db'} ) if $guid;
	}
	$self->{'prefs'} = $self->{'prefstore'}->get_all_general_prefs( $guid, $self->{'system'}->{'db'} );
	return;
}

sub _update_prefs {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $attribute = $q->param('attribute');
	return if !defined $attribute;
	my $value = $q->param('value');
	return if !defined $value;
	my %allowed_attributes =
	  map { $_ => 1 } qw(layout fill_gaps edit_elements remove_elements order elements default);
	if ( !$allowed_attributes{$attribute} ) {
		$logger->error("Invalid attribute - $attribute");
		return;
	}
	$attribute = "dashboard.$attribute";
	if ( $attribute eq 'layout' ) {
		my %allowed_values = map { $_ => 1 } ( 'left-top', 'right-top', 'left-bottom', 'right-bottom' );
		return if !$allowed_values{$value};
	}
	my %boolean_attributes = map { $_ => 1 } qw(fill_gaps edit_elements remove_elements);
	if ( $boolean_attributes{$attribute} ) {
		my %allowed_values = map { $_ => 1 } ( 0, 1 );
		return if !$allowed_values{$value};
	}
	my %json_attributes = map { $_ => 1 } qw(order elements);
	if ( $json_attributes{$attribute} ) {
		if ( length( $value > 5000 ) ) {
			$logger->error("$attribute value too long.");
			return;
		}
		eval { decode_json($value); };
		if ($@) {
			$logger->error("Invalid JSON for $attribute attribute");
		}
	}
	my $guid = $self->get_guid;
	$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, $attribute, $value );
	return;
}

sub print_panel_buttons {
	my ($self) = @_;
	say q(<span class="icon_button"><a class="trigger_button" id="panel_trigger" style="display:none">)
	  . q(<span class="fas fa-lg fa-wrench"></span><div class="icon_label">Dashboard settings</div></a></span>);
	say q(<span class="icon_button"><a class="trigger_button" id="dashboard_toggle">)
	  . q(<span class="fas fa-lg fa-th-list"></span><div class="icon_label">Index page</div></a></span>);
	return;
}

sub _print_modify_dashboard_fieldset {
	my ($self) = @_;
	my $layout          = $self->{'prefs'}->{'dashboard.layout'}          // 'left-top';
	my $fill_gaps       = $self->{'prefs'}->{'dashboard.fill_gaps'}       // 1;
	my $edit_elements   = $self->{'prefs'}->{'dashboard.edit_elements'}   // 0;
	my $remove_elements = $self->{'prefs'}->{'dashboard.remove_elements'} // 0;
	my $q               = $self->{'cgi'};
	say q(<div id="modify_panel" class="panel">);
	say q(<a class="trigger" id="close_trigger" href="#"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Dashboard settings</h2>);
	say q(<fieldset><legend>Layout</legend>);
	say q(<ul>);
	say q(<li><label for="layout">Orientation:</label>);
	say $q->popup_menu(
		-name   => 'layout',
		-id     => 'layout',
		-values => [ 'left-top', 'right-top', 'left-bottom', 'right-bottom' ],
		-labels => {
			'left-top'     => 'Left top',
			'right-top'    => 'Right top',
			'left-bottom'  => 'Left bottom',
			'right-bottom' => 'Right bottom'
		},
		-default => $layout
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'fill_gaps',
		-id      => 'fill_gaps',
		-label   => 'Fill gaps',
		-checked => $fill_gaps ? 'checked' : undef
	);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<fieldset><legend>Visual elements</legend>);
	say q(<ul><li>);
	say $q->checkbox(
		-name    => 'edit_elements',
		-id      => 'edit_elements',
		-label   => 'Enable options',
		-checked => $edit_elements ? 'checked' : undef
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'remove_elements',
		-id      => 'remove_elements',
		-label   => 'Enable removal',
		-checked => $remove_elements ? 'checked' : undef
	);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<div style="clear:both"></div>);
	say q(<fieldset><legend>Visual elements</legend>);
	say q(<ul><li>);

	if ( !LAYOUT_TEST ) {
		$self->_print_field_selector;
	}
	say q(<a id="add_element" class="small_submit">Add element</a>);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<div style="clear:both"></div>);
	say q(<div style="margin-top:2em">);
	say q(<a onclick="resetDefaults()" class="small_reset">Reset</a> Return to defaults);
	say q(</div></div>);
	return;
}

sub _print_field_selector {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $fields, $labels ) = $self->get_field_selection_list(
		{
			ignore_prefs        => 1,
			isolate_fields      => 1,
			scheme_fields       => 0,
			extended_attributes => 0,
			eav_fields          => 0,
		}
	);
	my $values           = [];
	my $group_members    = {};
	my $attributes       = $self->{'xmlHandler'}->get_all_field_attributes;
	my $eav_fields       = $self->{'datastore'}->get_eav_fields;
	my $eav_field_groups = { map { $_->{'field'} => $_->{'category'} } @$eav_fields };
	my %ignore           = map { $_ => 1 } ( 'f_id', "f_$self->{'system'}->{'labelfield'}" );

	foreach my $field (@$fields) {
		next if $ignore{$field};
		if ( $field =~ /^s_/x ) {
			push @{ $group_members->{'Schemes'} }, $field;
		}
		if ( $field =~ /^[f|e]_/x ) {
			( my $stripped_field = $field ) =~ s/^[f|e]_//x;
			$stripped_field =~ s/[\|\||\s].+$//x;
			if ( $attributes->{$stripped_field}->{'group'} ) {
				push @{ $group_members->{ $attributes->{$stripped_field}->{'group'} } }, $field;
			} else {
				push @{ $group_members->{'General'} }, $field;
			}
		}
		if ( $field =~ /^eav_/x ) {
			( my $stripped_field = $field ) =~ s/^eav_//x;
			if ( $eav_field_groups->{$stripped_field} ) {
				push @{ $group_members->{ $eav_field_groups->{$stripped_field} } }, $field;
			} else {
				push @{ $group_members->{'General'} }, $field;
			}
		}
	}
	my @group_list = split /,/x, ( $self->{'system'}->{'field_groups'} // q() );
	push @{ $group_members->{'Special'} }, 'sp_count';
	$labels->{'sp_count'} = "$self->{'system'}->{'labelfield'} count";
	my @eav_groups = split /,/x, ( $self->{'system'}->{'eav_groups'} // q() );
	push @group_list, @eav_groups if @eav_groups;
	push @group_list, ( 'Loci', 'Schemes' );
	foreach my $group ( 'Special', undef, @group_list ) {
		my $name = $group // 'General';
		$name =~ s/\|.+$//x;
		if ( ref $group_members->{$name} ) {
			push @$values, $q->optgroup( -name => $name, -values => $group_members->{$name}, -labels => $labels );
		}
	}
	say q(<label for="add_field">Field:</label>);
	say $q->popup_menu(
		-name     => 'add_field',
		-id       => 'add_field',
		-values   => $values,
		-labels   => $labels,
		-multiple => 'true',
		-style    => 'min-width:10em;width:15em;resize:both'
	);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $order = $self->{'prefs'}->{'dashboard.order'} // q();
	if ($order) {
		eval { decode_json($order); };
		if ($@) {
			$logger->error('Invalid order JSON');
			$order = q();
		}
	}
	my $elements      = $self->_get_elements;
	my $json_elements = encode_json($elements);
	my $empty         = $self->_get_dashboard_empty_message;
	my $buffer        = << "END";
var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}";
var elements = $json_elements;
var order = '$order';
var instance = "$self->{'instance'}";
var empty='$empty';

END
	return $buffer;
}
1;
