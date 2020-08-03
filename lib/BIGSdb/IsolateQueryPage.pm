#Written by Keith Jolley
#Copyright (c) 2010-2020, University of Oxford
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
package BIGSdb::IsolateQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::QueryPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use List::MoreUtils qw(any none);
use JSON;
use BIGSdb::Constants qw(:interface :limits SEQ_FLAGS LOCUS_PATTERN OPERATORS);
use constant WARN_IF_TAKES_LONGER_THAN_X_SECONDS => 5;
use constant MAX_LOCI_DROPDOWN                   => 200;

sub _ajax_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	if ( $q->param('add_filter') ) {
		$self->_set_filter_pref( scalar $q->param('add_filter'), 'add' );
		return;
	}
	if ( $q->param('remove_filter') ) {
		$self->_set_filter_pref( scalar $q->param('remove_filter'), 'remove' );
		return;
	}
	if ( $q->param('fieldset') ) {
		my %method = (
			phenotypic          => sub { $self->_print_phenotypic_fieldset_contents },
			allele_designations => sub { $self->_print_designations_fieldset_contents },
			allele_count        => sub { $self->_print_allele_count_fieldset_contents },
			allele_status       => sub { $self->_print_allele_status_fieldset_contents },
			tag_count           => sub { $self->_print_tag_count_fieldset_contents },
			tags                => sub { $self->_print_tags_fieldset_contents },
			list                => sub { $self->_print_list_fieldset_contents },
			filters             => sub { $self->_print_filters_fieldset_contents }
		);
		$method{ $q->param('fieldset') }->() if $method{ $q->param('fieldset') };
		return;
	}
	my $row = $q->param('row');
	return if !BIGSdb::Utils::is_int($row) || $row > MAX_ROWS || $row < 2;
	my %method = (
		provenance => sub {
			my ( $select_items, $labels ) = $self->_get_select_items;
			$self->_print_provenance_fields( $row, 0, $select_items, $labels );
		},
		phenotypic => sub {
			my ( $phenotypic_items, $phenotypic_labels ) =
			  $self->get_field_selection_list( { eav_fields => 1, sort_labels => 1 } );
			$self->_print_phenotypic_fields( $row, 0, $phenotypic_items, $phenotypic_labels );
		},
		loci => sub {
			my ( $locus_list, $locus_labels ) =
			  $self->get_field_selection_list(
				{ loci => 1, scheme_fields => 1, classification_groups => 1, sort_labels => 1 } );
			$self->_print_loci_fields( $row, 0, $locus_list, $locus_labels );
		},
		allele_count => sub {
			my ( $locus_list, $locus_labels ) =
			  $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
			$self->_print_allele_count_fields( $row, 0, $locus_list, $locus_labels );
		},
		allele_status => sub {
			my ( $locus_list, $locus_labels ) =
			  $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
			$self->_print_allele_status_fields( $row, 0, $locus_list, $locus_labels );
		},
		tag_count => sub {
			my ( $locus_list, $locus_labels ) =
			  $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
			$self->_print_tag_count_fields( $row, 0, $locus_list, $locus_labels );
		},
		tags => sub {
			my ( $locus_list, $locus_labels ) =
			  $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
			$self->_print_locus_tag_fields( $row, 0, $locus_list, $locus_labels );
		}
	);
	$method{ $q->param('fields') }->() if $method{ $q->param('fields') };
	return;
}

sub _set_filter_pref {
	my ( $self, $filter, $action ) = @_;
	my $q = $self->{'cgi'};
	return if !$filter;
	return if !$action;
	my $guid = $self->get_guid;
	return if !$guid;
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	my $extended   = $self->get_extended_attributes;
	foreach my $field (@$field_list) {

		if ( $filter eq $field ) {
			$self->{'prefs'}->{'dropdownfields'}->{$field} = $action eq 'add' ? 1 : 0;
			$self->{'prefstore'}
			  ->set_field( $guid, $self->{'system'}->{'db'}, $field, 'dropdown', $action eq 'add' ? 'true' : 'false' );
		}
		my $extatt = $extended->{$field} // [];
		foreach my $extended_attribute (@$extatt) {
			if ( $filter eq "${field}___$extended_attribute" ) {
				$self->{'prefs'}->{'dropdownfields'}->{"${field}..$extended_attribute"} = $action eq 'add' ? 1 : 0;
				$self->{'prefstore'}->set_field(
					$guid,
					$self->{'system'}->{'db'},
					"${field}..$extended_attribute",
					'dropdown', $action eq 'add' ? 'true' : 'false'
				);
			}
		}
	}
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,query_status FROM schemes', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $scheme (@$schemes) {
		my $field = "scheme_$scheme->{'id'}_profile_status";
		if ( $filter eq $field ) {
			$self->{'prefs'}->{'dropdownfields'}->{$field} = $action eq 'add' ? 1 : 0;
			$self->{'prefstore'}
			  ->set_field( $guid, $self->{'system'}->{'db'}, $field, 'dropdown', $action eq 'add' ? 'true' : 'false' );
		}
		my $fields = $self->{'datastore'}->get_scheme_fields( $scheme->{'id'} );
		foreach my $scheme_field (@$fields) {
			next if $filter ne "scheme_$scheme->{'id'}_$scheme_field";
			$self->{'prefs'}->{'dropdown_scheme_fields'}->{ $scheme->{'id'} }->{$scheme_field} =
			  $action eq 'add' ? 1 : 0;
			$self->{'prefstore'}->set_scheme_field(
				{
					guid      => $guid,
					dbase     => $self->{'system'}->{'db'},
					scheme_id => $scheme->{'id'},
					field     => $scheme_field,
					action    => 'dropdown',
					value     => $action eq 'add' ? 'true' : 'false'
				}
			);
		}
	}
	return;
}

sub get_help_url {
	my ($self) = @_;
	if ( $self->{'curate'} ) {
		return "$self->{'config'}->{'doclink'}/curator_guide.html#updating-and-deleting-single-isolate-records";
	} else {
		return "$self->{'config'}->{'doclink'}/data_query/0070_querying_isolate_data.html";
	}
}

sub _save_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	return if !$guid;
	foreach my $attribute (
		qw (provenance phenotypic allele_designations allele_count allele_status
		tag_count tags list filters)
	  )
	{
		my $value = $q->param($attribute) ? 'on' : 'off';
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, "${attribute}_fieldset", $value );
	}
	return;
}

sub get_title {
	my ($self) = @_;
	return $self->{'curate'} ? 'Query or update isolates' : 'Search or browse database';
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $scheme_info;
	if ( $q->param('no_header') ) {
		$self->_ajax_content;
		return;
	}
	if ( $q->param('save_options') ) {
		$self->_save_options;
		return;
	}
	if ( $q->param('add_to_project') ) {
		$self->add_to_project;
	}
	if ( $q->param('add_bookmark') ) {
		$self->add_bookmark;
	}
	if ( $q->param('publish') ) {
		$self->confirm_publication;
		return;
	}
	if ( $q->param('confirm_publish') ) {
		$self->publish;
	}
	my $title = $self->get_title;
	say qq(<h1>$title</h1>);
	my $qry;
	if ( !defined $q->param('currentpage') || $q->param('First') ) {
		say q(<noscript><div class="box statusbad"><p>This interface requires that you enable Javascript )
		  . q(in your browser.</p></div></noscript>);
		$self->_print_interface;
	}
	$self->_run_query if $q->param('submit') || defined $q->param('query_file');
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my $q      = $self->{'cgi'};
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say $q->start_form;
	say q(<p>Enter search criteria or leave blank to browse all records. Modify form parameters to filter or )
	  . q(enter a list of values.</p>);
	$q->param( table => $self->{'system'}->{'view'} );
	say $q->hidden($_) foreach qw (db page table set_id);
	say q(<div style="white-space:nowrap">);
	$self->_print_provenance_fields_fieldset;
	$self->_print_phenotypic_fields_fieldset;
	$self->_print_designations_fieldset;
	$self->_print_allele_count_fieldset;
	$self->_print_allele_status_fieldset;
	$self->_print_tag_count_fieldset;
	$self->_print_tags_fieldset;
	$self->_print_list_fieldset;
	$self->_print_filters_fieldset;
	$self->_print_display_fieldset;
	$self->print_action_fieldset( { submit_label => 'Search' } );
	$self->_print_modify_search_fieldset;
	$self->_print_bookmark_fieldset;
	say q(</div>);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub print_panel_buttons {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if (   !defined $q->param('currentpage')
		|| ( defined $q->param('pagejump') && $q->param('pagejump') eq '1' )
		|| $q->param('First') )
	{
		say q(<a class="trigger_button" id="panel_trigger" title="Modify form options" style="display:none">)
		  . q(<span class="fas fa-lg fa-wrench"></span></a>);
		my $bookmarks = $self->_get_bookmarks;
		if (@$bookmarks) {
			say q(<a class="trigger_button" id="bookmark_trigger" style="display:none" title="Bookmarks">)
			  . q(<span class="far fa-lg fa-bookmark"></span></a>);
		}
	}
	return;
}

sub _print_provenance_fields_fieldset {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my $display = $self->{'prefs'}->{'provenance_fieldset'}
	  || $self->_highest_entered_fields('provenance') ? 'inline' : 'none';
	say qq(<fieldset id="provenance_fieldset" style="float:left;display:$display">)
	  . q(<legend>Isolate provenance fields</legend>);
	my $prov_fields = $self->_highest_entered_fields('provenance') || 1;
	my $display_field_heading = $prov_fields == 1 ? 'none' : 'inline';
	say qq(<span id="prov_field_heading" style="display:$display_field_heading">)
	  . q(<label for="prov_andor">Combine with: </label>);
	say $q->popup_menu( -name => 'prov_andor', -id => 'prov_andor', -values => [qw (AND OR)] );
	say q(</span><ul id="provenance">);
	my ( $select_items, $labels ) = $self->_get_select_items;

	for ( 1 .. $prov_fields ) {
		say q(<li>);
		$self->_print_provenance_fields( $_, $prov_fields, $select_items, $labels );
		say q(</li>);
	}
	say q(</ul></fieldset>);
	return;
}

sub _print_phenotypic_fields_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM eav_fields)');
	say q(<fieldset id="phenotypic_fieldset" style="float:left;display:none">);
	my $field_name = ucfirst( $self->{'system'}->{'eav_fields'} // 'secondary metadata' );
	say qq(<legend>$field_name</legend><div>);
	if ( $self->_highest_entered_fields('phenotypic') ) {
		$self->_print_phenotypic_fieldset_contents;
	}
	say q(</div></fieldset>);
	return;
}

sub _print_display_fieldset {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	say q(<fieldset id="display_fieldset" style="float:left"><legend>Display/sort options</legend>);
	my ( $order_list, $labels ) =
	  $self->get_field_selection_list(
		{ isolate_fields => 1, loci => 1, scheme_fields => 1, locus_limit => MAX_LOCUS_ORDER_BY } );
	say q(<ul><li><span style="white-space:nowrap"><label for="order" class="display">Order by: </label>);
	say $self->popup_menu( -name => 'order', -id => 'order', -values => $order_list, -labels => $labels );
	say $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	say q(</span></li><li>);
	say $self->get_number_records_control;
	say q(</li></ul></fieldset>);
	return;
}

sub _print_designations_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="allele_designations_fieldset" style="float:left;display:none">);
	say q(<legend>Allele designations/scheme fields</legend><div>);

	#Get contents now if fieldset is visible, otherwise load via AJAX call
	if ( $self->_highest_entered_fields('loci') ) {
		$self->_print_designations_fieldset_contents;
	}
	say q(</div></fieldset>);
	return;
}

sub _print_designations_fieldset_contents {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list(
		{ loci => 1, scheme_fields => 1, classification_groups => 1, sort_labels => 1 } );
	if (@$locus_list) {
		my $locus_fields = $self->_highest_entered_fields('loci') || 1;
		my $loci_field_heading = $locus_fields == 1 ? 'none' : 'inline';
		say qq(<span id="loci_field_heading" style="display:$loci_field_heading">)
		  . q(<label for="c1">Combine with: </label>);
		say $q->popup_menu( -name => 'designation_andor', -id => 'designation_andor', -values => [qw (AND OR)], );
		say q(</span><ul id="loci">);
		for ( 1 .. $locus_fields ) {
			say q(<li>);
			$self->_print_loci_fields( $_, $locus_fields, $locus_list, $locus_labels );
			say q(</li>);
		}
		say q(</ul>);
	} else {
		say q(<p>No loci defined for query.</p>);
	}
	return;
}

sub _print_allele_count_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="allele_count_fieldset" style="float:left;display:none">);
	say q(<legend>Allele designation counts</legend><div>);

	#Get contents now if fieldset is visible, otherwise load via AJAX call
	if ( $self->_highest_entered_fields('allele_count') ) {
		$self->_print_allele_count_fieldset_contents;
	}
	say q(</div></fieldset>);
	return;
}

sub _print_allele_count_fieldset_contents {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
	if (@$locus_list) {
		my $locus_fields = $self->_highest_entered_fields('allele_count') || 1;
		my $heading_display = $locus_fields == 1 ? 'none' : 'inline';
		say qq(<span id="allele_count_field_heading" style="display:$heading_display">)
		  . q(<label for="count_andor">Combine with: </label>);
		say $q->popup_menu( -name => 'count_andor', -id => 'count_andor', -values => [qw (AND OR)] );
		say q(</span><ul id="allele_count">);
		for ( 1 .. $locus_fields ) {
			say q(<li>);
			$self->_print_allele_count_fields( $_, $locus_fields, $locus_list, $locus_labels );
			say q(</li>);
		}
		say q(</ul>);
	} else {
		say q(<p>No loci defined for query.</p>);
	}
	return;
}

sub _print_allele_status_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="allele_status_fieldset" style="float:left;display:none">);
	say q(<legend>Allele designation status</legend><div>);

	#Get contents now if fieldset is visible, otherwise load via AJAX call.
	if ( $self->_highest_entered_fields('allele_status') ) {
		$self->_print_allele_status_fieldset_contents;
	}
	say q(</div></fieldset>);
	return;
}

sub _print_allele_status_fieldset_contents {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
	if (@$locus_list) {
		my $locus_fields = $self->_highest_entered_fields('allele_status') || 1;
		my $heading_display = $locus_fields == 1 ? 'none' : 'inline';
		say qq(<span id="allele_status_field_heading" style="display:$heading_display">)
		  . q(<label for="designation_andor">Combine with: </label>);
		say $q->popup_menu( -name => 'status_andor', -id => 'status_andor', -values => [qw (AND OR)] );
		say q(</span><ul id="allele_status">);
		for ( 1 .. $locus_fields ) {
			say q(<li>);
			$self->_print_allele_status_fields( $_, $locus_fields, $locus_list, $locus_labels );
			say q(</li>);
		}
		say q(</ul>);
	} else {
		say q(<p>No loci defined for query.</p>);
	}
	return;
}

sub _print_tag_count_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM allele_sequences)');
	say q(<fieldset id="tag_count_fieldset" style="float:left;display:none">);
	say q(<legend>Tagged sequence counts</legend><div>);
	if ( $self->_highest_entered_fields('tag_count') ) {
		$self->_print_tag_count_fieldset_contents;
	}
	say q(</div></fieldset>);
	return;
}

sub _print_tag_count_fieldset_contents {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
	if (@$locus_list) {
		my $tag_count_fields = $self->_highest_entered_fields('tag_count') || 1;
		my $tag_count_heading = $tag_count_fields == 1 ? 'none' : 'inline';
		say qq(<span id="tag_count_heading" style="display:$tag_count_heading">)
		  . q(<label for="tag_count_andor">Combine with: </label>);
		say $q->popup_menu( -name => 'tag_count_andor', -id => 'tag_count_andor', -values => [qw (AND OR)] );
		say q(</span><ul id="tag_count">);
		for ( 1 .. $tag_count_fields ) {
			say q(<li>);
			$self->_print_tag_count_fields( $_, $tag_count_fields, $locus_list, $locus_labels );
			say q(</li>);
		}
		say q(</ul>);
	} else {
		say q(<p>No loci defined for query.</p>);
	}
	return;
}

sub _print_tags_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM allele_sequences)');
	say q(<fieldset id="tags_fieldset" style="float:left;display:none">);
	say q(<legend>Tagged sequence status</legend><div>);
	if ( $self->_highest_entered_fields('tags') ) {
		$self->_print_tags_fieldset_contents;
	}
	say q(</div></fieldset>);
	$self->{'tags_fieldset_exists'} = 1;
	return;
}

sub _print_tags_fieldset_contents {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
	if (@$locus_list) {
		my $locus_tag_fields = $self->_highest_entered_fields('tags') || 1;
		my $locus_tags_heading = $locus_tag_fields == 1 ? 'none' : 'inline';
		say qq(<span id="locus_tags_heading" style="display:$locus_tags_heading">)
		  . q(<label for="designation_andor">Combine with: </label>);
		say $q->popup_menu( -name => 'tag_andor', -id => 'tag_andor', -values => [qw (AND OR)] );
		say q(</span><ul id="tags">);
		for ( 1 .. $locus_tag_fields ) {
			say q(<li>);
			$self->_print_locus_tag_fields( $_, $locus_tag_fields, $locus_list, $locus_labels );
			say q(</li>);
		}
		say q(</ul>);
	} else {
		say q(<p>No loci defined for query.</p>);
	}
	return;
}

sub _print_list_fieldset {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my $display = $self->{'prefs'}->{'list_fieldset'}
	  || $q->param('list') ? 'inline' : 'none';
	say
	  qq(<fieldset id="list_fieldset" style="float:left;display:$display"><legend>Attribute values list</legend><div>);
	if ( $q->param('list') ) {
		$self->_print_list_fieldset_contents;
	}
	say q(</div></fieldset>);
	return;
}

sub _print_list_fieldset_contents {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my @grouped_fields;
	my ( $field_list, $labels ) = $self->get_field_selection_list(
		{
			isolate_fields      => 1,
			eav_fields          => 1,
			loci                => 1,
			scheme_fields       => 1,
			sender_attributes   => 0,
			extended_attributes => 1
		}
	);
	my $grouped = $self->{'xmlHandler'}->get_grouped_fields;
	foreach (@$grouped) {
		push @grouped_fields, "f_$_";
		( $labels->{"f_$_"} = $_ ) =~ tr/_/ /;
	}
	say q(Field:);
	say $self->popup_menu( -name => 'attribute', -values => $field_list, -labels => $labels );
	say q(<br />);
	say $q->textarea(
		-name        => 'list',
		-id          => 'list',
		-rows        => 6,
		-style       => 'width:100%',
		-placeholder => 'Enter list of values (one per line)...'
	);
	return;
}

sub _modify_query_by_list {
	my ( $self, $qry ) = @_;
	my $q = $self->{'cgi'};
	return $qry if !$q->param('list');
	my $attribute_data = $self->_get_list_attribute_data( scalar $q->param('attribute') );
	my ( $field, $extended_field, $scheme_id, $field_type, $data_type, $eav_table, $optlist, $multiple ) =
	  @{$attribute_data}{qw (field extended_field scheme_id field_type data_type eav_table optlist multiple)};
	return $qry if !$field;
	my @list = split /\n/x, $q->param('list');
	if ($optlist) {
		my %used = map { $_ => 1 } @list;
		foreach my $value (@list) {
			my $subvalues = $self->_get_sub_values( $value, $optlist );
			foreach my $subvalue (@$subvalues) {
				push @list, $subvalue if !$used{$subvalue};
				$used{$subvalue} = 1;
			}
		}
	}
	BIGSdb::Utils::remove_trailing_spaces_from_list( \@list );
	my $list = $self->clean_list( $data_type, \@list );
	$self->{'datastore'}->create_temp_list_table_from_array( $data_type, $list, { table => 'temp_list' } );
	my $list_file = BIGSdb::Utils::get_random() . '.list';
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for writing");
	say $fh $_ foreach @$list;
	close $fh;
	$q->param( list_file => $list_file );
	$q->param( datatype  => $data_type );
	my $view                      = $self->{'system'}->{'view'};
	my $isolate_scheme_field_view = q();

	if ( $field_type eq 'scheme_field' ) {
		$isolate_scheme_field_view = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
	}
	$field_type = 'provenance_multiple' if $field_type eq 'provenance' && $multiple;
	my %sql = (
		labelfield => ( $data_type eq 'text' ? "UPPER($view.$field) " : "$view.$field " )
		  . "IN (SELECT value FROM temp_list) OR $view.id IN (SELECT isolate_id FROM isolate_aliases "
		  . 'WHERE UPPER(alias) IN (SELECT value FROM temp_list))',
		provenance => ( $data_type eq 'text' ? "UPPER($view.$field)" : "$view.$field" )
		  . ' IN (SELECT value FROM temp_list)',
		provenance_multiple => $data_type eq 'text'
		? "UPPER($view.$field\::text)::text[] && ARRAY(SELECT value FROM temp_list)"
		: "$view.$field && ARRAY(SELECT value FROM temp_list)",
		phenotypic => "$view.id IN (SELECT isolate_id FROM $eav_table WHERE field=E'$field' AND "
		  . ( $data_type eq 'text' ? 'UPPER(value)' : 'value' )
		  . ' IN (SELECT value FROM temp_list))',
		extended_isolate => "$view.$extended_field IN (SELECT field_value FROM isolate_value_extended_attributes "
		  . "WHERE isolate_field='$extended_field' AND attribute='$field' AND "
		  . ( $data_type eq 'text' ? 'UPPER(value)' : 'value' )
		  . ' IN (SELECT value FROM temp_list))',
		locus => "$view.id IN (SELECT isolate_id FROM allele_designations WHERE locus=E'$field' AND allele_id IN "
		  . '(SELECT value FROM temp_list))',
		scheme_field => "$view.id IN (SELECT id FROM $isolate_scheme_field_view WHERE "
		  . ( $data_type eq 'text' ? "UPPER($field)" : $field )
		  . ' IN (SELECT value FROM temp_list))'
	);
	return $qry if !$sql{$field_type};
	if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
		$qry .= " AND ($sql{$field_type})";
	} else {
		$qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE ($sql{$field_type})";
	}
	return $qry;
}

sub _get_list_attribute_data {
	my ( $self, $attribute ) = @_;
	my $pattern = LOCUS_PATTERN;
	my ( $field, $extended_field, $scheme_id, $field_type, $data_type, $eav_table, $optlist, $multiple );
	if ( $attribute =~ /^s_(\d+)_(\S+)$/x ) {    ## no critic (ProhibitCascadingIfElse)
		$scheme_id  = $1;
		$field      = $2;
		$field_type = 'scheme_field';
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		$data_type = $scheme_field_info->{'type'};
		return if !$scheme_field_info;
	} elsif ( $attribute =~ /$pattern/x ) {
		$field      = $1;
		$field_type = 'locus';
		$data_type  = 'text';
		return if !$self->{'datastore'}->is_locus($field);
		$field =~ s/\'/\\'/gx;
	} elsif ( $attribute =~ /^f_(\S+)$/x ) {
		$field      = $1;
		$field_type = 'provenance';
		$field_type = 'labelfield'
		  if $field_type eq 'provenance' && $field eq $self->{'system'}->{'labelfield'};
		return if !$self->{'xmlHandler'}->is_field($field);
		my $field_info = $self->{'xmlHandler'}->get_field_attributes($field);
		$data_type = $field_info->{'type'};
		if ( ( $field_info->{'optlist'} // q() ) eq 'yes' ) {
			$optlist = $self->{'xmlHandler'}->get_field_option_list($field);
		}
		if ( ( $field_info->{'multiple'} // q() ) eq 'yes' ) {
			$multiple = 1;
		}
	} elsif ( $attribute =~ /^eav_(\S+)$/x ) {
		$field      = $1;
		$field_type = 'phenotypic';
		my $field_info = $self->{'datastore'}->get_eav_field($field);
		return if !$field_info;
		$data_type = $field_info->{'value_format'};
		$eav_table = $self->{'datastore'}->get_eav_table($data_type);
	} elsif ( $attribute =~ /^e_(.*)\|\|(.*)/x ) {
		$extended_field = $1;
		$field          = $2;
		$data_type      = 'text';
		$field_type     = 'extended_isolate';
	}
	$_ //= q() foreach ( $eav_table, $extended_field );
	return {
		field          => $field,
		eav_table      => $eav_table,
		extended_field => $extended_field,
		scheme_id      => $scheme_id,
		field_type     => $field_type,
		data_type      => $data_type,
		optlist        => $optlist,
		multiple       => $multiple
	};
}

sub _print_filters_fieldset {
	my ($self) = @_;
	say q(<fieldset id="filters_fieldset" style="float:left;display:none"><legend>Filters</legend>);
	say q(<div>);
	$self->_print_filters_fieldset_contents;
	say q(</div>);
	say q(</fieldset>);
	return;
}

sub _get_inactive_filters {
	my ($self)     = @_;
	my $set_id     = $self->get_set_id;
	my $is_curator = $self->is_curator;
	my $field_list = $self->{'xmlHandler'}->get_field_list( { no_curate_only => !$is_curator } );
	my $list       = [];
	my $labels     = {};
	my $extended   = $self->get_extended_attributes;
	foreach my $field (@$field_list) {
		next if $field eq 'id';
		if ( !$self->{'prefs'}->{'dropdownfields'}->{$field} ) {
			( my $id = $field ) =~ tr/:/_/;
			push @$list, $id;
			$labels->{$id} = $field;
		}
		my $extatt = $extended->{$field} // [];
		foreach my $extended_attribute (@$extatt) {
			next if $self->{'prefs'}->{'dropdownfields'}->{"$field\..$extended_attribute"};
			push @$list, "${field}___$extended_attribute";
			$labels->{"${field}___$extended_attribute"} = $extended_attribute;
		}
	}
	my %labels;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => 1 } );
	foreach my $scheme (@$schemes) {
		my $field = "scheme_$scheme->{'id'}\_profile_status";
		if ( !$self->{'prefs'}->{'dropdownfields'}->{$field} ) {
			push @$list, $field;
			$labels->{$field} = "$scheme->{'name'} profile completion";
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $scheme->{'id'} );
		foreach my $field (@$scheme_fields) {
			next if $self->{'prefs'}->{'dropdown_scheme_fields'}->{ $scheme->{'id'} }->{$field};
			push @$list, "scheme_$scheme->{'id'}_$field";
			$labels->{"scheme_$scheme->{'id'}_$field"} = "$field ($scheme->{'name'})";
		}
	}
	return ( $list, $labels );
}

sub _print_filters_fieldset_contents {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my @filters;
	my $buffer = $self->get_isolate_publication_filter( { any => 1, multiple => 1 } );
	push @filters, $buffer if $buffer;
	$buffer = $self->get_project_filter( { any => 1, multiple => 1 } );
	push @filters, $buffer if $buffer;

	#Enable filters if used in bookmark.
	if ( defined $self->{'temp_prefs'}->{'dropdownfields'} ) {
		foreach my $key ( keys %{ $self->{'temp_prefs'}->{'dropdownfields'} } ) {
			if ( $self->{'temp_prefs'}->{'dropdownfields'}->{$key} ) {
				$self->{'prefs'}->{'dropdownfields'}->{$key} = 1;
			}
		}
	}
	my $field_filters = $self->_get_field_filters;
	push @filters, @$field_filters if @$field_filters;
	my $profile_filters = $self->_get_profile_filters;
	push @filters, @$profile_filters;
	my $seqbin_filter = $self->_get_seqbin_filter;
	push @filters, $seqbin_filter if $seqbin_filter;
	my $private_data_filter = $self->_get_private_data_filter;
	push @filters, $private_data_filter if $private_data_filter;
	push @filters, $self->get_old_version_filter;
	say q(<ul>);
	say qq(<li><span style="white-space:nowrap">$_</span></li>) foreach @filters;
	say q(</ul>);
	my ( $list, $labels ) = $self->_get_inactive_filters;

	if (@$list) {
		unshift @$list, q();
		say q(<span style="white-space:nowrap">);
		say q(Add filter:);
		say $self->popup_menu(
			-name   => 'new_filter',
			-id     => 'new_filter',
			-values => $list,
			-labels => $labels,
			-style  => 'max-width:25em'
		);
		say q( <a id="add_filter" class="small_submit">Add</a>);
		say q(</span>);
	}
	say << "JS";
<script>
\$(function () {
	\$("#add_filter").on('click',function(){
		var filter = \$("#new_filter").val();
		if (filter == ""){
			return;
		}
		\$.ajax({
			url: "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query&no_header=1&add_filter=" 
			 + filter,
			success: function(response){
				refresh_filters();
			}
		})		
	});
	\$(".remove_filter").on('click',function(){
		var filter = \$(this).attr('id').replace(/^remove_/,'');
		if (filter == ""){
			return;
		}
		\$.ajax({
			url: "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query&no_header=1&remove_filter=" 
			 + filter,
			success: function(response){
				refresh_filters();
			}
		})		
	});
});	
</script>
JS
	return;
}

sub _print_modify_search_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div id="modify_panel" class="panel">);
	say q(<a class="close_trigger" id="close_trigger"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Modify form parameters</h2>);
	say q(<p>Click to add or remove additional query terms:</p><ul style="list-style:none;margin-left:-2em">);
	my $provenance_fieldset_display = $self->_should_display_fieldset('provenance') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_provenance">$provenance_fieldset_display</a>);
	say q(Provenance fields</li>);

	if ( $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM eav_fields)') ) {
		my $phenotypic_fieldset_display = $self->_should_display_fieldset('phenotypic') ? HIDE : SHOW;
		my $field_name = ucfirst( $self->{'system'}->{'eav_fields'} // 'secondary metadata' );
		say qq(<li><a href="" class="button" id="show_phenotypic">$phenotypic_fieldset_display</a>);
		say qq($field_name</li>);
	}
	my $allele_designations_fieldset_display = $self->_should_display_fieldset('allele_designations') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_allele_designations">$allele_designations_fieldset_display</a>);
	say q(Allele designations/scheme field values</li>);
	my $allele_count_fieldset_display = $self->_should_display_fieldset('allele_count') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_allele_count">$allele_count_fieldset_display</a>);
	say q(Allele designation counts</li>);
	my $allele_status_fieldset_display = $self->_should_display_fieldset('allele_status') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_allele_status">$allele_status_fieldset_display</a>);
	say q(Allele designation status</li>);

	if ( $self->{'tags_fieldset_exists'} ) {
		my $tag_count_fieldset_display = $self->_should_display_fieldset('tag_count') ? HIDE : SHOW;
		say qq(<li><a href="" class="button" id="show_tag_count">$tag_count_fieldset_display</a>);
		say q(Tagged sequence counts</li>);
		my $tags_fieldset_display = $self->_should_display_fieldset('tags') ? HIDE : SHOW;
		say qq(<li><a href="" class="button" id="show_tags">$tags_fieldset_display</a>);
		say q(Tagged sequence status</li>);
	}
	my $list_fieldset_display = $self->{'prefs'}->{'list_fieldset'}
	  || $q->param('list') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_list">$list_fieldset_display</a>);
	say q(Attribute values list</li>);
	my $filters_fieldset_display = $self->{'prefs'}->{'filters_fieldset'}
	  || $self->filters_selected ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_filters">$filters_fieldset_display</a>);
	say q(Filters</li>);
	say q(</ul>);
	my $save = SAVE;
	say qq(<a id="save_options" class="button" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=query&amp;save_options=1" style="display:none">$save</a> <span id="saving"></span><br />);
	say q(</div>);
	return;
}

sub _get_bookmarks {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return [] if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return [] if !$user_info;
	my $bookmarks =
	  $self->{'datastore'}->run_query( 'SELECT id,name,dbase_config FROM bookmarks WHERE user_id=? ORDER BY name',
		$user_info->{'id'}, { fetch => 'all_arrayref', slice => {} } );
	return $bookmarks;
}

sub _print_bookmark_fieldset {
	my ($self) = @_;
	my $bookmarks = $self->_get_bookmarks;
	return if !@$bookmarks;
	say q(<div id="bookmark_panel" style="display:none">);
	say q(<a class="close_trigger" id="close_bookmark"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Bookmarks</h2>);
	say q(<div><div style="max-height:12em;overflow-y:auto;padding-right:2em"><ul style="margin-left:-1em">);
	foreach my $bookmark (@$bookmarks) {
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$bookmark->{'dbase_config'}&amp;)
		  . qq(page=query&amp;bookmark=$bookmark->{'id'}">$bookmark->{'name'}</a></li>);
	}
	say q(</ul></div>);
	say qq(<p style="margin-top:1em"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . q(page=bookmarks">Manage bookmarks</a></p>);
	say q(</div></div>);
	return;
}

sub _get_profile_filters {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my @filters;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => 1 } );
	foreach my $scheme (@$schemes) {
		my $field = "scheme_$scheme->{'id'}_profile_status";
		if ( $self->{'prefs'}->{'dropdownfields'}->{$field} ) {
			push @filters,
			  $self->get_filter(
				$field,
				[ 'complete', 'incomplete', 'partial', 'started', 'not started' ],
				{
					text    => "$scheme->{'name'} profiles",
					tooltip => "$scheme->{'name'} profile completion filter - Select whether the isolates should "
					  . 'have complete, partial, or unstarted profiles.',
					capitalize_first => 1,
					remove_id        => "remove_scheme_$scheme->{'id'}_profile_status"
				}
			  );
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $scheme->{'id'} );
		foreach my $field (@$scheme_fields) {
			if ( $self->{'prefs'}->{'dropdown_scheme_fields'}->{ $scheme->{'id'} }->{$field} ) {
				my $values = $self->{'datastore'}->get_scheme( $scheme->{'id'} )->get_distinct_fields($field);
				if (@$values) {
					my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme->{'id'}, $field );
					if ( $scheme_field_info->{'type'} eq 'integer' ) {
						@$values = sort { $a <=> $b } @$values;
					}
					my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/x ? 'an' : 'a';
					push @filters,
					  $self->get_filter(
						"scheme_$scheme->{'id'}_$field",
						$values,
						{
							text => "$field ($scheme->{'name'})",
							tooltip =>
							  "$field ($scheme->{'name'}) filter - Select $a_or_an $field to filter your search "
							  . "to only those isolates that match the selected $field.",
							capitalize_first => 1,
							remove_id        => "remove_scheme_$scheme->{'id'}_$field"
						}
					  );
				}
			}
		}
	}
	return \@filters;
}

sub _get_seqbin_filter {
	my ($self) = @_;
	my $linked_seqs = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ($linked_seqs) {
		my @values = ( 'Any sequence data', 'No sequence data' );
		if ( $self->{'system'}->{'seqbin_size_threshold'} ) {
			foreach my $value ( split /,/x, $self->{'system'}->{'seqbin_size_threshold'} ) {
				push @values, "Sequence bin size >= $value Mbp";
			}
		}
		return $self->get_filter(
			'linked_sequences',
			\@values,
			{
				text    => 'Sequence bin',
				tooltip => 'sequence bin filter - Filter by whether the isolate record has sequence data attached.'
			}
		);
	}
	return;
}

sub _get_private_data_filter {
	my ($self) = @_;
	return if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !$user_info;
	my $private =
	    $self->{'curate'}
	  ? $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM private_isolates)')
	  : $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM private_isolates WHERE user_id=?)', $user_info->{'id'} );
	return if !$private;
	my $labels = {
		1 => 'my private records only',
		2 => 'private records (in quota)',
		3 => 'private records (excluded from quota)',
		4 => 'private records (requesting publication)',
		5 => 'public records only'
	};
	return $self->get_filter(
		'private_records',
		[ 1 .. 5 ],
		{
			labels  => $labels,
			text    => 'Private records',
			tooltip => 'private records filter - Filter by whether the isolate record is private. '
			  . 'The default is to include both your private and public records.'
		}
	);
}

sub _get_field_filters {
	my ($self)     = @_;
	my $prefs      = $self->{'prefs'};
	my $filters    = [];
	my $extended   = $self->get_extended_attributes;
	my $set_id     = $self->get_set_id;
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	foreach my $field (@$field_list) {
		my $thisfield      = $self->{'xmlHandler'}->get_field_attributes($field);
		my $dropdownlist   = [];
		my $dropdownlabels = { null => '[null]' };
		if ( $prefs->{'dropdownfields'}->{$field} ) {
			if (   $field eq 'sender'
				|| $field eq 'curator'
				|| ( ( $thisfield->{'userfield'} // q() ) eq 'yes' ) )
			{
				push @$filters,
				  $self->get_user_filter( $field, { capitalize_first => 1, remove_id => "remove_$field" } );
			} else {
				if ( ( $thisfield->{'optlist'} // q() ) eq 'yes' ) {
					$dropdownlist = $self->{'xmlHandler'}->get_field_option_list($field);
					if ( ( $thisfield->{'required'} // q() ) eq 'no' ) {
						push @$dropdownlist, 'null';
					}
				} elsif ( ( $thisfield->{'multiple'} // q() ) eq 'yes' ) {
					my $list = $self->{'datastore'}->run_query(
						"SELECT DISTINCT(UNNEST($field)) AS $field FROM $self->{'system'}->{'view'} "
						  . "WHERE $field IS NOT NULL ORDER BY $field",
						undef,
						{ fetch => 'col_arrayref' }
					);
					push @$dropdownlist, @$list;
					if ( ( $thisfield->{'required'} // q() ) eq 'no' ) {
						push @$dropdownlist, 'null';
					}
				} else {
					my $list = $self->{'datastore'}->run_query(
						"SELECT DISTINCT($field) FROM $self->{'system'}->{'view'} "
						  . "WHERE $field IS NOT NULL ORDER BY $field",
						undef,
						{ fetch => 'col_arrayref' }
					);
					push @$dropdownlist, @$list;
					if ( ( $thisfield->{'required'} // q() ) eq 'no' ) {
						push @$dropdownlist, 'null';
					}
				}
				my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/x ? 'an' : 'a';
				my $display_field = $field;
				push @$filters,
				  $self->get_filter(
					$field,
					$dropdownlist,
					{
						labels => $dropdownlabels,
						tooltip =>
						  "$display_field filter - Select $a_or_an $display_field to filter your search to only those "
						  . "isolates that match the selected $display_field.",
						capitalize_first => 1,
						remove_id        => "remove_$field"
					}
				  ) if @$dropdownlist;
			}
		}
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( $self->{'prefs'}->{'dropdownfields'}->{"$field\..$extended_attribute"} ) {
					my $values = $self->{'datastore'}->run_query(
						'SELECT DISTINCT value FROM isolate_value_extended_attributes '
						  . 'WHERE isolate_field=? AND attribute=? ORDER BY value',
						[ $field, $extended_attribute ],
						{ fetch => 'col_arrayref' }
					);
					push @$values, 'null';
					my $a_or_an = substr( $extended_attribute, 0, 1 ) =~ /[aeiouAEIOU]/x ? 'an' : 'a';
					push @$filters,
					  $self->get_filter(
						"${field}___$extended_attribute",
						$values,
						{
							labels => $dropdownlabels,
							text   => $extended_attribute,
							tooltip =>
							  "$extended_attribute filter - Select $a_or_an $extended_attribute to filter your "
							  . "search to only those isolates that match the selected $field.",
							capitalize_first => 1,
							remove_id        => "remove_${field}___$extended_attribute"
						}
					  );
				}
			}
		}
	}
	return $filters;
}

sub _print_provenance_fields {
	my ( $self, $row, $max_rows, $select_items, $labels ) = @_;
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	say $q->popup_menu(
		-name   => "prov_field$row",
		-id     => "prov_field$row",
		-values => $select_items,
		-labels => $labels,
		-class  => 'fieldlist'
	);
	say $q->popup_menu( -name => "prov_operator$row", -values => [OPERATORS] );
	say $q->textfield(
		-name        => "prov_value$row",
		-id          => "prov_value$row",
		-class       => 'value_entry',
		-placeholder => 'Enter value...'
	);
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_fields" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
		  . qq(fields=provenance&amp;row=$next_row&amp;no_header=1" data-rel="ajax" class="add_button"><span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'prov_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _print_phenotypic_fields {
	my ( $self, $row, $max_rows, $select_items, $labels ) = @_;
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	say $q->popup_menu(
		-name   => "phenotypic_field$row",
		-id     => "phenotypic_field$row",
		-values => $select_items,
		-labels => $labels,
		-class  => 'fieldlist'
	);
	say $q->popup_menu( -name => "phenotypic_operator$row", -values => [OPERATORS] );
	say $q->textfield(
		-name        => "phenotypic_value$row",
		-id          => "phenotypic_value$row",
		-class       => 'value_entry',
		-placeholder => 'Enter value...'
	);
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_phenotypic_fields" href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=query&amp;)
		  . qq(fields=phenotypic&amp;row=$next_row&amp;no_header=1" data-rel="ajax" class="add_button">)
		  . q(<span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'phenotypic_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _print_phenotypic_fieldset_contents {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $list, $labels ) =
	  $self->get_field_selection_list( { eav_fields => 1, sort_labels => 1 } );
	if (@$list) {
		my $phenotypic_fields = $self->_highest_entered_fields('phenotypic') || 1;
		my $phenotypic_heading = $phenotypic_fields == 1 ? 'none' : 'inline';
		say qq(<span id="phenotypic_field_heading" style="display:$phenotypic_heading">)
		  . q(<label for="phenotypic_andor">Combine with: </label>);
		say $q->popup_menu( -name => 'phenotypic_andor', -id => 'phenotypic_andor', -values => [qw (AND OR)] );
		say q(</span><ul id="phenotypic">);
		for my $row ( 1 .. $phenotypic_fields ) {
			say q(<li>);
			$self->_print_phenotypic_fields( $row, $phenotypic_fields, $list, $labels );
			say q(</li>);
		}
		say q(</ul>);
	} else {
		say q(<p>No loci defined for query.</p>);
	}
	return;
}

sub _print_allele_status_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, 'any locus';
	unshift @$locus_list, '';
	$locus_labels->{''} = ' ';    #Required for HTML5 validation.
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	if ( @$locus_list > MAX_LOCI_DROPDOWN ) {
		say $self->datalist(
			name            => "allele_status_field$row",
			id              => "allele_status_field$row",
			values          => $locus_list,
			labels          => $locus_labels,
			class           => 'fieldlist',
			invalid_value   => 'l_INVALID',
			datalist_name   => 'allele_status_list',
			datalist_exists => $row == 1 ? 0 : 1
		);
	} else {
		say $self->popup_menu(
			-name   => "allele_status_field$row",
			-id     => "allele_status_field$row",
			-values => $locus_list,
			-labels => $locus_labels,
			-class  => 'fieldlist'
		);
	}
	print ' is ';
	my $values = [ '', 'provisional', 'confirmed' ];
	my %labels = ( '' => ' ' );    #Required for HTML5 validation.
	say $q->popup_menu(
		-name   => "allele_status_value$row",
		-id     => "allele_status_value$row",
		-values => $values,
		-labels => \%labels
	);
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_allele_status" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=query&amp;fields=allele_status&amp;row=$next_row&amp;no_header=1" data-rel="ajax" )
		  . q(class="add_button"><span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'allele_status_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _print_allele_count_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, 'any locus';
	unshift @$locus_list, 'total designations';
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	say q(Count of );
	if ( @$locus_list > MAX_LOCI_DROPDOWN ) {
		say $self->datalist(
			name            => "allele_count_field$row",
			id              => "allele_count_field$row",
			values          => $locus_list,
			labels          => $locus_labels,
			class           => 'fieldlist',
			invalid_value   => 'l_INVALID',
			datalist_name   => 'allele_count_list',
			datalist_exists => $row == 1 ? 0 : 1
		);
	} else {
		say $self->popup_menu(
			-name   => "allele_count_field$row",
			-id     => "allele_count_field$row",
			-values => $locus_list,
			-labels => $locus_labels,
			-class  => 'fieldlist'
		);
	}
	my $values = [ '>', '<', '=' ];
	say $q->popup_menu( -name => "allele_count_operator$row", -id => "allele_count_operator$row", -values => $values );
	my %args = (
		-name        => "allele_count_value$row",
		-id          => "allele_count_value$row",
		-class       => 'int_entry',
		-type        => 'number',
		-min         => 0,
		-placeholder => 'Enter...',
	);
	$args{'-value'} = $q->param("allele_count_value$row") if defined $q->param("allele_count_value$row");
	say $self->textfield(%args);
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_allele_count" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=query&amp;fields=allele_count&amp;row=$next_row&amp;no_header=1" data-rel="ajax" )
		  . q(class="add_button"><span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'allele_count_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _print_loci_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, '';
	if ( @$locus_list <= MAX_LOCI_DROPDOWN ) {
		$locus_labels->{''} = ' ';    #Required for HTML5 validation.
	}
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	if ( @$locus_list > MAX_LOCI_DROPDOWN ) {
		say $self->datalist(
			name            => "designation_field$row",
			id              => "designation_field$row",
			values          => $locus_list,
			labels          => $locus_labels,
			class           => 'fieldlist',
			invalid_value   => 'l_INVALID',
			datalist_name   => 'designation_field_list',
			datalist_exists => $row == 1 ? 0 : 1
		);
	} else {
		say $self->popup_menu(
			-name   => "designation_field$row",
			-id     => "designation_field$row",
			-values => $locus_list,
			-labels => $locus_labels,
			-class  => 'fieldlist'
		);
	}
	say $q->popup_menu(
		-name   => "designation_operator$row",
		-id     => "designation_operator$row",
		-values => [OPERATORS]
	);
	say $q->textfield(
		-name        => "designation_value$row",
		-id          => "designation_value$row",
		-class       => 'value_entry',
		-placeholder => 'Enter value...'
	);
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_loci" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=query&amp;fields=loci&amp;row=$next_row&amp;no_header=1" data-rel="ajax" class="add_button">)
		  . q(<span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'loci_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _print_locus_tag_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, 'any locus';
	unshift @$locus_list, '';
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	if ( @$locus_list > MAX_LOCI_DROPDOWN ) {
		say $self->datalist(
			name            => "tag_field$row",
			id              => "tag_field$row",
			values          => $locus_list,
			labels          => $locus_labels,
			class           => 'fieldlist',
			invalid_value   => 'l_INVALID',
			datalist_name   => 'tag_list',
			datalist_exists => $row == 1 ? 0 : 1
		);
	} else {
		say $self->popup_menu(
			-name   => "tag_field$row",
			-id     => "tag_field$row",
			-values => $locus_list,
			-labels => $locus_labels,
			-class  => 'fieldlist'
		);
	}
	print ' is ';
	my @values = qw(untagged tagged complete incomplete);
	push @values, "flagged: $_" foreach ( 'any', 'none', SEQ_FLAGS );
	unshift @values, '';
	my %labels = ( '' => ' ' );    #Required for HTML5 validation.
	say $q->popup_menu( -name => "tag_value$row", -id => "tag_value$row", values => \@values, -labels => \%labels );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_tags" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=query&amp;fields=tags&amp;row=$next_row&amp;no_header=1" data-rel="ajax" class="add_button">)
		  . q(<span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'tag_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _print_tag_count_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, 'any locus';
	unshift @$locus_list, 'total tags';
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	say q(Count of );
	if ( @$locus_list > MAX_LOCI_DROPDOWN ) {
		say $self->datalist(
			name            => "tag_count_field$row",
			id              => "tag_count_field$row",
			values          => $locus_list,
			labels          => $locus_labels,
			class           => 'fieldlist',
			invalid_value   => 'l_INVALID',
			datalist_name   => 'tag_count_list',
			datalist_exists => $row == 1 ? 0 : 1
		);
	} else {
		say $self->popup_menu(
			-name   => "tag_count_field$row",
			-id     => "tag_count_field$row",
			-values => $locus_list,
			-labels => $locus_labels,
			-class  => 'fieldlist'
		);
	}
	my $values = [ '>', '<', '=' ];
	say $q->popup_menu( -name => "tag_count_operator$row", -id => "tag_count_operator$row", -values => $values );
	my %args = (
		-name        => "tag_count_value$row",
		-id          => "tag_count_value$row",
		-class       => 'int_entry',
		-type        => 'number',
		-min         => 0,
		-placeholder => 'Enter...',
	);
	$args{'-value'} = $q->param("tag_count_value$row") if defined $q->param("tag_count_value$row");
	say $self->textfield(%args);
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_tag_count" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=query&amp;fields=tag_count&amp;row=$next_row&amp;no_header=1" data-rel="ajax" )
		  . q(class="add_button"><span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'tag_count_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _run_query {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $qry;
	my $errors     = [];
	my $extended   = $self->get_extended_attributes;
	my $start_time = time;
	if ( !defined $q->param('query_file') ) {
		$qry = $self->_generate_query_for_provenance_fields($errors);
		$qry = $self->_modify_query_for_eav_fields( $qry, $errors );
		$qry = $self->_modify_query_by_list($qry);
		$qry = $self->_modify_query_for_filters( $qry, $extended );
		$qry = $self->_modify_query_for_designations( $qry, $errors );
		$qry = $self->_modify_query_for_designation_counts( $qry, $errors );
		$qry = $self->_modify_query_for_tags( $qry, $errors );
		$qry = $self->_modify_query_for_tag_counts( $qry, $errors );
		$qry = $self->_modify_query_for_designation_status( $qry, $errors );
		$qry .= ' ORDER BY ';

		if ( defined $q->param('order')
			&& ( $q->param('order') =~ /^la_(.+)\|\|/x || $q->param('order') =~ /^cn_(.+)/x ) )
		{
			$qry .= "l_$1";
		} else {
			$qry .= $q->param('order') || 'id';
		}
		my $dir =
		  ( defined $q->param('direction') && $q->param('direction') eq 'descending' ) ? 'desc' : 'asc';

		#Adding additional ordering by datestamp
		#See http://stackoverflow.com/questions/21385555/postgresql-query-very-slow-with-limit-1
		#This changed a query against an isolate extended field from 10s -> 43ms!
		$qry .= " $dir,$self->{'system'}->{'view'}.id,$self->{'system'}->{'view'}.datestamp;";
	} else {
		$qry = $self->get_query_from_temp_file( scalar $q->param('query_file') );
		if ( $q->param('list_file') && $q->param('attribute') ) {
			my $attribute_data = $self->_get_list_attribute_data( scalar $q->param('attribute') );
			$self->{'datastore'}
			  ->create_temp_list_table( $attribute_data->{'data_type'}, scalar $q->param('list_file') );
		}
	}
	my $browse;
	if ( $qry =~ /\(\)/x ) {
		$qry =~ s/\ WHERE\ \(\)//x;
		$browse = 1;
	}
	if (@$errors) {
		local $" = '<br />';
		$self->print_bad_status( { message => q(Problem with search criteria:), detail => qq(@$errors) } );
	} else {
		my $view              = $self->{'system'}->{'view'};
		my $hidden_attributes = $self->get_hidden_attributes;
		$qry =~ s/\ datestamp/\ $view\.datestamp/gx;
		$qry =~ s/\(datestamp/\($view\.datestamp/gx;
		my $args = {
			table             => $self->{'system'}->{'view'},
			query             => $qry,
			browse            => $browse,
			hidden_attributes => $hidden_attributes
		};
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	}
	my $elapsed = time - $start_time;
	if ( $elapsed > WARN_IF_TAKES_LONGER_THAN_X_SECONDS && $self->{'datastore'}->{'scheme_not_cached'} ) {
		$logger->warn( "$self->{'instance'}: Query took $elapsed seconds.  Schemes are not cached for this "
			  . 'database.  You should consider running the update_scheme_caches.pl script regularly against '
			  . 'this database to create these caches.' );
	}
	return;
}

sub get_hidden_attributes {
	my ($self) = @_;
	my $extended = $self->get_extended_attributes;
	my @hidden_attributes;
	push @hidden_attributes, qw (prov_andor phenotypic_andor designation_andor tag_andor status_andor);
	for my $row ( 1 .. MAX_ROWS ) {
		push @hidden_attributes, "prov_field$row", "prov_value$row", "prov_operator$row", "phenotypic_field$row",
		  "phenotypic_value$row", "phenotypic_operator$row", "designation_field$row",
		  "designation_operator$row", "designation_value$row", "tag_field$row", "tag_value$row",
		  "allele_status_field$row",
		  "allele_status_value$row", "allele_count_field$row", "allele_count_operator$row",
		  "allele_count_value$row", "tag_count_field$row", "tag_count_operator$row", "tag_count_value$row";
	}
	foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
		push @hidden_attributes, "${field}_list";
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				push @hidden_attributes, "${field}..$extended_attribute\_list";
			}
		}
	}
	push @hidden_attributes, qw(publication_list project_list linked_sequences_list private_records_list
	  include_old list list_file attribute datatype);
	my $schemes = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	foreach my $scheme_id (@$schemes) {
		push @hidden_attributes, "scheme_$scheme_id\_profile_status_list";
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		push @hidden_attributes, "scheme_$scheme_id\_$_\_list" foreach (@$scheme_fields);
	}
	return \@hidden_attributes;
}

sub _generate_query_for_provenance_fields {
	my ( $self, $errors_ref ) = @_;
	my $q           = $self->{'cgi'};
	my $view        = $self->{'system'}->{'view'};
	my $qry         = "SELECT * FROM $view WHERE (";
	my $andor       = $q->param('prov_andor') || 'AND';
	my $first_value = 1;
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("prov_value$i") && $q->param("prov_value$i") ne '' ) {
			my $field = $q->param("prov_field$i");
			$field =~ s/^f_//x;
			my @groupedfields = $self->get_grouped_fields($field);
			my $thisfield     = $self->{'xmlHandler'}->get_field_attributes($field);
			my $optlist;
			if ( ( $thisfield->{'optlist'} // q() ) eq 'yes' ) {
				$optlist = $self->{'xmlHandler'}->get_field_option_list($field);
			}
			my $extended_isolate_field;
			my $parent_field_type;
			if ( $field =~ /^e_(.*)\|\|(.*)/x ) {
				$extended_isolate_field = $1;
				$field                  = $2;
				my $att_info = $self->{'datastore'}->run_query(
					'SELECT * FROM isolate_field_extended_attributes WHERE (isolate_field,attribute)=(?,?)',
					[ $extended_isolate_field, $field ],
					{ fetch => 'row_hashref' }
				);
				if ( !$att_info ) {
					push @$errors_ref, 'Invalid field selected.';
					next;
				}
				$parent_field_type =
				  $self->{'xmlHandler'}->get_field_attributes( $att_info->{'isolate_field'} )->{'type'};
				$thisfield->{'type'} = $att_info->{'value_format'};
				$thisfield->{'type'} = 'int' if $thisfield->{'type'} eq 'integer';
			}
			my $operator = $q->param("prov_operator$i") // '=';
			my $text = $q->param("prov_value$i");
			$self->process_value( \$text );
			next
			  if $self->check_format(
				{ field => $field, text => $text, type => lc( $thisfield->{'type'} // '' ), operator => $operator },
				$errors_ref );
			my $modifier = ( $i > 1 && !$first_value ) ? " $andor " : '';
			$first_value = 0;
			if ( $field =~ /(.*)\ \(id\)$/x
				&& !BIGSdb::Utils::is_int($text) )
			{
				push @$errors_ref, "$field is an integer field.";
				next;
			}
			if ( any { $field =~ /(.*)\ \($_\)$/x } qw (id surname first_name affiliation) ) {
				$qry .= $modifier . $self->search_users( $field, $operator, $text, $view );
			} else {
				if (@groupedfields) {
					$qry .=
					  $self->_grouped_field_query( \@groupedfields,
						{ text => $text, operator => $operator, modifier => $modifier }, $errors_ref );
					next;
				}
				if ( !$extended_isolate_field ) {
					if ( !$self->{'xmlHandler'}->is_field($field) ) {
						push @$errors_ref, "$field is an invalid field.";
						next;
					}
					$field = "$view.$field";
				}
				my $args = {
					field                  => $field,
					extended_isolate_field => $extended_isolate_field,
					text                   => $text,
					modifier               => $modifier,
					type                   => $thisfield->{'type'},
					multiple               => ( $thisfield->{'multiple'} // q() ) eq 'yes' ? 1 : 0,
					parent_field_type      => $parent_field_type,
					operator               => $operator,
					optlist                => $optlist,
					errors                 => $errors_ref
				};
				my %method = (
					'NOT' => sub {
						$args->{'not'} = 1;
						$qry .= $self->_provenance_equals_type_operator($args);
					},
					'contains' => sub {
						$args->{'behaviour'} = '%text%';
						$qry .= $self->_provenance_like_type_operator($args);
					},
					'starts with' => sub {
						$args->{'behaviour'} = 'text%';
						$qry .= $self->_provenance_like_type_operator($args);
					},
					'ends with' => sub {
						$args->{'behaviour'} = '%text';
						$qry .= $self->_provenance_like_type_operator($args);
					},
					'NOT contain' => sub {
						$args->{'behaviour'} = '%text%';
						$args->{'not'}       = 1;
						$qry .= $self->_provenance_like_type_operator($args);
					},
					'=' => sub {
						$qry .= $self->_provenance_equals_type_operator($args);
					},
					'>' => sub {
						$qry .= $self->_provenance_ltmt_type_operator($args);
					},
					'>=' => sub {
						$qry .= $self->_provenance_ltmt_type_operator($args);
					},
					'<' => sub {
						$qry .= $self->_provenance_ltmt_type_operator($args);
					},
					'<=' => sub {
						$qry .= $self->_provenance_ltmt_type_operator($args);
					}
				);
				$method{$operator}->();
			}
		}
	}
	$qry .= ')';
	return $qry;
}

sub _grouped_field_query {
	my ( $self, $groupedfields, $data, $errors_ref ) = @_;
	my $text     = $data->{'text'};
	my $operator = $data->{'operator'} // '=';
	my $view     = $self->{'system'}->{'view'};
	my $buffer   = "$data->{'modifier'} (";
	my %methods  = (
		'NOT' => sub {
			foreach my $field (@$groupedfields) {
				my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				if ( lc($text) eq 'null' ) {
					$buffer .= ' OR ' if $field ne $groupedfields->[0];
					$buffer .= "($view.$field IS NOT NULL)";
				} else {
					$buffer .= ' AND ' if $field ne $groupedfields->[0];
					$buffer .=
					  $thisfield->{'type'} eq 'text'
					  ? "(NOT UPPER($view.$field) = UPPER(E'$text') OR $view.$field IS NULL)"
					  : "(NOT CAST($view.$field AS text) = E'$text' OR $view.$field IS NULL)";
				}
			}
		},
		'contains' => sub {
			foreach my $field (@$groupedfields) {
				my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				$buffer .= ' OR ' if $field ne $groupedfields->[0];
				$buffer .=
				  $thisfield->{'type'} eq 'text'
				  ? "UPPER($view.$field) LIKE UPPER(E'\%$text\%')"
				  : "CAST($view.$field AS text) LIKE E'\%$text\%'";
			}
		},
		'starts with' => sub {
			foreach my $field (@$groupedfields) {
				my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				$buffer .= ' OR ' if $field ne $groupedfields->[0];
				$buffer .=
				  $thisfield->{'type'} eq 'text'
				  ? "UPPER($view.$field) LIKE UPPER(E'$text\%')"
				  : "CAST($view.$field AS text) LIKE E'$text\%'";
			}
		},
		'ends with' => sub {
			foreach my $field (@$groupedfields) {
				my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				$buffer .= ' OR ' if $field ne $groupedfields->[0];
				$buffer .=
				  $thisfield->{'type'} eq 'text'
				  ? "UPPER($view.$field) LIKE UPPER(E'\%$text')"
				  : "CAST($view.$field AS text) LIKE E'\%$text'";
			}
		},
		'NOT contain' => sub {
			foreach my $field (@$groupedfields) {
				my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				$buffer .= ' AND ' if $field ne $groupedfields->[0];
				$buffer .=
				  $thisfield->{'type'} eq 'text'
				  ? "(NOT UPPER($view.$field) LIKE UPPER(E'\%$text\%') OR $view.$field IS NULL)"
				  : "(NOT CAST($view.$field AS text) LIKE E'\%$text\%' OR $view.$field IS NULL)";
			}
		},
		'=' => sub {
			foreach my $field (@$groupedfields) {
				my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				$buffer .= ' OR ' if $field ne $groupedfields->[0];
				if ( lc($text) eq 'null' ) {
					$buffer .= "$view.$field IS NULL";
				} else {
					$buffer .=
					  $thisfield->{'type'} eq 'text'
					  ? "UPPER($view.$field) = UPPER(E'$text')"
					  : "CAST($view.$field AS text) = E'$text'";
				}
			}
		}
	);
	if ( $methods{$operator} ) {
		$methods{$operator}->();
	} else {    # less than or greater than
		foreach my $field (@$groupedfields) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			return
			  if $self->check_format(
				{ field => $field, text => $text, type => $thisfield->{'type'}, operator => $data->{'operator'} },
				$errors_ref );
			$buffer .= ' OR ' if $field ne $groupedfields->[0];
			$buffer .=
			  $thisfield->{'type'} eq 'text'
			  ? "($view.$field $operator E'$text' AND $view.$field IS NOT NULL)"
			  : "(CAST($view.$field AS text) $operator E'$text' AND $view.$field IS NOT NULL)";
		}
	}
	$buffer .= ')';
	return $buffer;
}

sub _provenance_equals_type_operator {
	my ( $self, $values ) = @_;
	my ( $field, $extended_isolate_field, $text, $parent_field_type, $type, $multiple, $optlist ) =
	  @$values{qw(field extended_isolate_field text parent_field_type type multiple optlist)};
	my $buffer     = $values->{'modifier'};
	my $view       = $self->{'system'}->{'view'};
	my $labelfield = "$view.$self->{'system'}->{'labelfield'}";
	my $not        = $values->{'not'} ? 'NOT' : '';
	my $inv_not    = $values->{'not'} ? '' : 'NOT';
	if ($extended_isolate_field) {
		$buffer .=
		  $parent_field_type eq 'int'
		  ? "CAST($view.$extended_isolate_field AS text) "
		  : "UPPER($view.$extended_isolate_field) ";
		if ( lc($text) eq 'null' ) {
			$buffer .= "$inv_not IN (SELECT UPPER(field_value) FROM isolate_value_extended_attributes "
			  . "WHERE isolate_field='$extended_isolate_field' AND attribute='$field')";
		} else {
			$buffer .= "$not IN (SELECT UPPER(field_value) FROM isolate_value_extended_attributes WHERE isolate_field="
			  . "'$extended_isolate_field' AND attribute='$field' AND UPPER(value) = UPPER(E'$text'))";
		}
	} elsif ( $field eq $labelfield ) {
		$buffer .=
		    "($not UPPER($field) = UPPER(E'$text') "
		  . ( $values->{'not'} ? ' AND ' : ' OR ' )
		  . "$view.id $not IN (SELECT isolate_id FROM isolate_aliases WHERE "
		  . "UPPER(alias) = UPPER(E'$text')))";
	} else {
		my $null_clause = $values->{'not'} ? "OR $field IS NULL" : '';
		if ( lc($text) eq 'null' ) {
			$buffer .= "$field IS $not null";
		} elsif ( lc($type) eq 'text' ) {
			my $subvalues = $self->_get_sub_values( $text, $optlist );
			if ($multiple) {
				$buffer .= "(($not E'$text' ILIKE ANY($field)) $null_clause)";
			} else {
				my $subvalue_clause = q();
				if ($subvalues) {
					foreach my $subvalue (@$subvalues) {
						$subvalue =~ s/'/\\'/gx;
						$subvalue_clause .= " OR UPPER($field) = UPPER(E'$subvalue')";
					}
				}
				$buffer .= "(($not (UPPER($field) = UPPER(E'$text')$subvalue_clause)) $null_clause)";
			}
		} else {
			if ($multiple) {
				$buffer .= "(($not E'$text' = ANY($field)) $null_clause)";
			} else {
				$buffer .= "($not ($field = E'$text') $null_clause)";
			}
		}
	}
	return $buffer;
}

sub _get_sub_values {
	my ( $self, $value, $optlist ) = @_;
	return if !ref $optlist;
	return if $value =~ /\[.+\]$/x;
	my $subvalues;
	foreach my $option (@$optlist) {
		push @$subvalues, $option if $option =~ /^$value\ \[.+\]$/ix;
	}
	return $subvalues;
}

sub _provenance_like_type_operator {
	my ( $self, $values ) = @_;
	my ( $field, $extended_isolate_field, $parent_field_type, $type, $multiple ) =
	  @$values{qw(field extended_isolate_field parent_field_type type multiple)};
	my $buffer     = $values->{'modifier'};
	my $view       = $self->{'system'}->{'view'};
	my $labelfield = "$view.$self->{'system'}->{'labelfield'}";
	my $not        = $values->{'not'} ? 'NOT' : '';
	( my $text = $values->{'behaviour'} ) =~ s/text/$values->{'text'}/;
	if ($extended_isolate_field) {
		$buffer .=
		  $parent_field_type eq 'int'
		  ? "CAST($view.$extended_isolate_field AS text) "
		  : "$view.$extended_isolate_field ";
		$buffer .=
		    "$not IN (SELECT field_value FROM isolate_value_extended_attributes "
		  . "WHERE isolate_field='$extended_isolate_field' AND attribute='$field' "
		  . "AND value ILIKE E'$text')";
	} elsif ( $field eq $labelfield ) {
		my $andor = $values->{'not'} ? 'AND' : 'OR';
		$buffer .= "($not $field ILIKE E'$text' $andor $view.id $not IN "
		  . "(SELECT isolate_id FROM isolate_aliases WHERE alias ILIKE E'$text'))";
	} else {
		my $null_clause = $values->{'not'} ? "OR $field IS NULL" : '';
		my $rand = 'x' . int( rand(99999999) );
		if ( $type ne 'text' ) {
			if ($multiple) {
				$buffer .=
				    "($view.id $not IN (SELECT $view.id FROM $view,unnest($field) "
				  . "$rand WHERE CAST($rand AS text) ILIKE E'$text') $null_clause)";
			} else {
				$buffer .= "($not CAST($field AS text) LIKE E'$text' $null_clause)";
			}
		} else {
			if ($multiple) {
				$buffer .=
				    "($view.id $not IN (SELECT $view.id FROM $view,unnest($field) "
				  . "$rand WHERE $rand ILIKE E'$text') $null_clause)";
			} else {
				$buffer .= "($not $field ILIKE E'$text' $null_clause)";
			}
		}
	}
	return $buffer;
}

sub _provenance_ltmt_type_operator {
	my ( $self, $values ) = @_;
	my ( $field, $extended_isolate_field, $text, $parent_field_type, $operator, $errors, $multiple ) =
	  @$values{qw(field extended_isolate_field text parent_field_type operator errors multiple)};
	my $buffer     = $values->{'modifier'};
	my $view       = $self->{'system'}->{'view'};
	my $labelfield = "$view.$self->{'system'}->{'labelfield'}";
	if ($extended_isolate_field) {
		$buffer .=
		  $parent_field_type eq 'int'
		  ? "CAST($view.$extended_isolate_field AS text) "
		  : "$view.$extended_isolate_field ";
		$buffer .= 'IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='
		  . "'$extended_isolate_field' AND attribute='$field' AND value $operator E'$text')";
	} elsif ( $field eq $labelfield ) {
		$buffer .= "($field $operator '$text' OR $view.id IN (SELECT isolate_id FROM isolate_aliases "
		  . "WHERE alias $operator E'$text'))";
	} else {
		if ( lc($text) eq 'null' ) {
			push @$errors, "$operator is not a valid operator for comparing null values.";
			return q();
		}
		if ($multiple) {

			#We have to write the query the other way round when using ARRAYs.
			my %rev_operator = (
				'>'  => '<',
				'<'  => '>',
				'>=' => '<=',
				'<=' => '>='
			);
			$buffer .= "E'$text' $rev_operator{$operator} ANY($field)";
		} else {
			$buffer .= "$field $operator E'$text'";
		}
	}
	return $buffer;
}

sub _modify_query_for_filters {
	my ( $self, $qry, $extended ) = @_;    #extended: extended attributes hashref
	my $q          = $self->{'cgi'};
	my $view       = $self->{'system'}->{'view'};
	my $set_id     = $self->get_set_id;
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	my $att        = $self->{'xmlHandler'}->get_all_field_attributes;
	foreach my $field (@$field_list) {
		my $multiple = ( $att->{$field}->{'multiple'} // q() ) eq 'yes';
		if ( defined $q->param("${field}_list") && $q->param("${field}_list") ne '' ) {
			my $value = $q->param("${field}_list");
			if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
				$qry .= ' AND (';
			} else {
				$qry = "SELECT * FROM $view WHERE (";
			}
			$value =~ s/'/\\'/x;
			if ( lc($value) eq 'null' ) {
				$qry .= "$view.$field is null";
			} else {
				$qry .=
				    $multiple                          ? "E'$value' = ANY($view.$field)"
				  : $att->{$field}->{'type'} eq 'text' ? "UPPER($view.$field) = UPPER(E'$value')"
				  :                                      "$view.$field = E'$value'";
				my $optlist = $self->{'xmlHandler'}->get_field_option_list($field);
				my $subvalues = $self->_get_sub_values( $value, $optlist );
				if ($subvalues) {
					foreach my $subvalue (@$subvalues) {
						$subvalue =~ s/'/\\'/x;
						$qry .=
						  $multiple
						  ? " OR E'$subvalue' = ANY($view.$field)"
						  : " OR UPPER($view.$field) = UPPER(E'$subvalue')";
					}
				}
			}
			$qry .= ')';
		}
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( defined $q->param("${field}___${extended_attribute}_list")
					&& $q->param("${field}___${extended_attribute}_list") ne '' )
				{
					my $value = $q->param("${field}___${extended_attribute}_list");
					$value =~ s/'/\\'/gx;
					if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
						$qry .= ' AND ';
					} else {
						$qry = "SELECT * FROM $view WHERE ";
					}
					if ( $value eq 'null' ) {
						$qry .= "$field NOT IN (SELECT field_value FROM isolate_value_extended_attributes "
						  . "WHERE isolate_field='$field' AND attribute='$extended_attribute')";
					} else {
						$qry .=
						    "(UPPER($field) IN (SELECT UPPER(field_value) FROM "
						  . "isolate_value_extended_attributes WHERE isolate_field='$field' AND "
						  . "attribute='$extended_attribute' AND value='$value'))";
					}
				}
			}
		}
	}
	$self->_modify_query_by_membership(
		{ qry_ref => \$qry, table => 'refs', param => 'publication_list', query_field => 'pubmed_id' } );
	$self->_modify_query_by_membership(
		{ qry_ref => \$qry, table => 'project_members', param => 'project_list', query_field => 'project_id' } );
	if ( $q->param('linked_sequences_list') ) {
		my $not         = '';
		my $size_clause = '';
		if ( $q->param('linked_sequences_list') eq 'No sequence data' ) {
			$not = ' NOT ';
		} elsif ( $q->param('linked_sequences_list') =~ />=\ ([\d\.]+)\ Mbp/x ) {
			my $size = $1 * 1000000;    #Mbp
			$size_clause = " AND seqbin_stats.total_length >= $size";
		}
		if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
			$qry .= " AND (${not}EXISTS (SELECT 1 FROM seqbin_stats WHERE "
			  . "seqbin_stats.isolate_id = $view.id$size_clause))";
		} else {
			$qry = "SELECT * FROM $view WHERE (${not}EXISTS (SELECT 1 FROM seqbin_stats WHERE "
			  . "seqbin_stats.isolate_id=$view.id$size_clause))";
		}
	}
	$self->_modify_query_by_profile_status( \$qry );
	$self->_modify_query_by_private_status( \$qry );
	if ( !$q->param('include_old') ) {
		if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
			$qry .= " AND ($view.new_version IS NULL)";
		} else {
			$qry = "SELECT * FROM $view WHERE ($view.new_version IS NULL)";
		}
	}
	return $qry;
}

sub _modify_query_by_profile_status {
	my ( $self, $qry_ref ) = @_;
	my $q       = $self->{'cgi'};
	my $view    = $self->{'system'}->{'view'};
	my $schemes = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	foreach my $scheme_id (@$schemes) {
		if ( ( $q->param("scheme_${scheme_id}_profile_status_list") // q() ) ne '' ) {
			my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
			if (@$scheme_loci) {
				my $table       = $self->{'datastore'}->create_temp_scheme_status_table($scheme_id);
				my $param       = $q->param("scheme_${scheme_id}_profile_status_list");
				my $locus_count = @$scheme_loci;
				my %clause      = (
					complete => "$view.id IN (SELECT id FROM $table WHERE locus_count=$locus_count)",
					partial  => "$view.id IN (SELECT id FROM $table WHERE locus_count<$locus_count AND locus_count>0)",
					started  => "$view.id IN (SELECT id FROM $table WHERE locus_count>0)",
					incomplete => "$view.id IN (SELECT id FROM $table WHERE locus_count<$locus_count) "
					  . "OR $view.id NOT IN (SELECT id FROM $table)",
					'not started' => "$view.id NOT IN (SELECT id FROM $table)"
				);
				if ( $$qry_ref !~ /WHERE\ \(\)\s*$/x ) {
					$$qry_ref .= " AND ($clause{$param})";
				} else {
					$$qry_ref = "SELECT * FROM $view WHERE ($clause{$param})";
				}
			}
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach (@$scheme_fields) {

			#Copy field value rather than use reference directly since we modify it and it may be needed elsewhere.
			my $field = $_;
			if ( ( $q->param("scheme_$scheme_id\_$field\_list") // '' ) ne '' ) {
				my $value = $q->param("scheme_$scheme_id\_$field\_list");
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				my $isolate_scheme_field_view =
				  $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				$field = "$isolate_scheme_field_view\.$field";
				local $" = ' AND ';
				my $temp_qry = "SELECT $isolate_scheme_field_view.id FROM $isolate_scheme_field_view";
				$value =~ s/'/\\'/gx;
				my $clause =
				  $scheme_field_info->{'type'} eq 'text'
				  ? "($view.id IN ($temp_qry WHERE UPPER($field) = UPPER(E'$value')))"
				  : "($view.id IN  ($temp_qry WHERE CAST($field AS int) = E'$value'))";

				if ( $$qry_ref !~ /WHERE\ \(\)\s*$/x ) {
					$$qry_ref .= "AND $clause";
				} else {
					$$qry_ref = "SELECT * FROM $view WHERE $clause";
				}
			}
		}
	}
	return;
}

sub _modify_query_by_private_status {
	my ( $self, $qry_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	return if !$q->param('private_records_list');
	return if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !$user_info;
	my $clause;
	my $my_private   = "$view.id IN (SELECT isolate_id FROM private_isolates WHERE user_id=$user_info->{'id'})";
	my $not_in_quota = 'EXISTS(SELECT 1 FROM projects p JOIN project_members pm ON '
	  . "p.id=pm.project_id WHERE no_quota AND pm.isolate_id=$view.id)";
	my $term = {
		1 => sub { $clause = "($my_private)" },
		2 => sub { $clause = "($my_private AND NOT $not_in_quota)" },
		3 => sub { $clause = "($my_private AND $not_in_quota)" },
		4 => sub { $clause = "(EXISTS(SELECT 1 FROM private_isolates WHERE request_publish AND isolate_id=$view.id))" },
		5 => sub { $clause = "(NOT EXISTS(SELECT 1 FROM private_isolates WHERE isolate_id=$view.id))" }
	};

	if ( $term->{ $q->param('private_records_list') } ) {
		$term->{ $q->param('private_records_list') }->();
	} else {
		return;
	}
	if ( $$qry_ref !~ /WHERE\ \(\)\s*$/x ) {
		$$qry_ref .= "AND $clause";
	} else {
		$$qry_ref = "SELECT * FROM $view WHERE $clause";
	}
	return;
}

sub _modify_query_by_membership {

	#Modify query for membership of PubMed paper or project
	my ( $self, $args ) = @_;
	my ( $qry_ref, $table, $param, $query_field ) = @{$args}{qw(qry_ref table param query_field)};
	my $q = $self->{'cgi'};
	return if !$q->param($param);
	my @list = $q->multi_param($param);
	my $subqry;
	my $view = $self->{'system'}->{'view'};
	if ( any { $_ eq 'any' } @list ) {
		$subqry = "$view.id IN (SELECT isolate_id FROM $table)";
	}
	if ( any { $_ eq 'none' } @list ) {
		$subqry .= ' OR ' if $subqry;
		$subqry .= "$view.id NOT IN (SELECT isolate_id FROM $table)";
	}
	if ( any { BIGSdb::Utils::is_int($_) } @list ) {
		my @int_list = grep { BIGSdb::Utils::is_int($_) } @list;
		$subqry .= ' OR ' if $subqry;
		local $" = ',';
		$subqry .= "$view.id IN (SELECT isolate_id FROM $table WHERE $query_field IN (@int_list))";
	}
	if ($subqry) {
		if ( $$qry_ref !~ /WHERE\ \(\)\s*$/x ) {
			$$qry_ref .= " AND ($subqry)";
		} else {
			$$qry_ref = "SELECT * FROM $view WHERE ($subqry)";
		}
	}
	return;
}

sub _modify_query_for_eav_fields {
	my ( $self, $qry, $errors ) = @_;
	my $q     = $self->{'cgi'};
	my $view  = $self->{'system'}->{'view'};
	my $andor = ( $q->param('phenotypic_andor') // '' ) eq 'AND' ? ' AND ' : ' OR ';
	my %combo;
	my @sub_qry;
	foreach my $i ( 1 .. MAX_ROWS ) {
		next if !defined $q->param("phenotypic_value$i") || $q->param("phenotypic_value$i") eq q();
		( my $field = $q->param("phenotypic_field$i") ) =~ s/^eav_//x;
		my $field_info = $self->{'datastore'}->get_eav_field($field);
		if ( !$field_info ) {
			push @$errors, 'Invalid secondary metadata field name selected.';
			next;
		}
		my $eav_table = $self->{'datastore'}->get_eav_table( $field_info->{'value_format'} );
		( my $cleaned_field = $field ) =~ s/'/\\'/gx;
		my $operator = $q->param("phenotypic_operator$i") // '=';
		my $text = $q->param("phenotypic_value$i");
		next if $combo{"${field}_${operator}_$text"};    #prevent duplicates
		$combo{"${field}_${operator}_$text"} = 1;
		$self->process_value( \$text );
		next
		  if $self->check_format(
			{ field => $field, text => $text, type => $field_info->{'value_format'}, operator => $operator }, $errors );
		my %methods = (
			'NOT' => sub {

				if ( lc($text) eq 'null' ) {
					push @sub_qry, "($view.id IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field'))";
				} else {
					push @sub_qry,
					  $field_info->{'value_format'} eq 'text'
					  ? "($view.id NOT IN (SELECT isolate_id FROM $eav_table WHERE "
					  . "(field,UPPER(value))=(E'$cleaned_field',UPPER(E'$text'))))"
					  : "($view.id NOT IN (SELECT isolate_id FROM $eav_table WHERE "
					  . "(field,CAST (value AS text))=(E'$cleaned_field',E'$text')))";
				}
			},
			'contains' => sub {
				push @sub_qry,
				  $field_info->{'value_format'} eq 'text'
				  ? "($view.id IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field' "
				  . " AND UPPER(value) LIKE upper(E'\%$text\%')))"
				  : "($view.id IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field' "
				  . " AND CAST(value AS text) LIKE (E'\%$text\%')))";
			},
			'starts with' => sub {
				push @sub_qry,
				  $field_info->{'value_format'} eq 'text'
				  ? "($view.id IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field' "
				  . " AND UPPER(value) LIKE upper(E'$text\%')))"
				  : "($view.id IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field' "
				  . " AND CAST(value AS text) LIKE (E'$text\%')))";
			},
			'ends with' => sub {
				push @sub_qry,
				  $field_info->{'value_format'} eq 'text'
				  ? "($view.id IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field' "
				  . " AND UPPER(value) LIKE upper(E'\%$text')))"
				  : "($view.id IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field' "
				  . " AND CAST(value AS text) LIKE (E'\%$text')))";
			},
			'NOT contain' => sub {
				push @sub_qry,
				  $field_info->{'value_format'} eq 'text'
				  ? "($view.id NOT IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field' "
				  . " AND UPPER(value) LIKE upper(E'\%$text\%')))"
				  : "($view.id NOT IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field' "
				  . " AND CAST(value AS text) LIKE (E'\%$text\%')))";
			},
			'=' => sub {
				if ( lc($text) eq 'null' ) {
					push @sub_qry,
					  "($view.id NOT IN (SELECT isolate_id FROM $eav_table WHERE field=E'$cleaned_field'))";
				} else {
					push @sub_qry,
					  $field_info->{'value_format'} eq 'text'
					  ? "($view.id IN (SELECT isolate_id FROM $eav_table WHERE "
					  . "(field,UPPER(value))=(E'$cleaned_field',UPPER(E'$text'))))"
					  : "($view.id IN (SELECT isolate_id FROM $eav_table WHERE "
					  . "(field,CAST(value AS text))=(E'$cleaned_field',E'$text')))";
				}
			}
		);
		if ( $methods{$operator} ) {
			$methods{$operator}->();
		} else {
			if ( lc($text) eq 'null' ) {
				push @$errors, "$operator is not a valid operator for comparing null values.";
				next;
			}
			push @sub_qry,
			  "($view.id IN (SELECT isolate_id FROM $eav_table WHERE field = E'$cleaned_field' "
			  . "AND value $operator E'$text'))";
		}
	}
	if (@sub_qry) {
		local $" = $andor;
		if ( $qry =~ /\(\)$/x ) {
			$qry = "SELECT * FROM $view WHERE (@sub_qry)";
		} else {
			$qry .= " AND (@sub_qry)";
		}
	}
	return $qry;
}

sub _modify_query_for_designations {
	my ( $self, $qry, $errors ) = @_;
	my $q     = $self->{'cgi'};
	my $view  = $self->{'system'}->{'view'};
	my $andor = ( $q->param('designation_andor') // '' ) eq 'AND' ? ' AND ' : ' OR ';
	my ( $queries_by_locus, $locus_null_queries ) = $self->_get_allele_designations( $errors, $andor );
	my @null_queries = @$locus_null_queries;
	my ( $scheme_queries, $scheme_null_queries ) = $self->_get_scheme_designations($errors);
	push @null_queries, @$scheme_null_queries;
	my ( $cgroup_queries, $cgroup_null_queries ) = $self->_get_classification_group_designations($errors);
	push @null_queries, @$cgroup_null_queries;
	my @designation_queries;

	if ( keys %$queries_by_locus ) {
		local $" = ' OR ';
		my $modify = '';
		if ( ( $q->param('designation_andor') // '' ) eq 'AND' ) {
			my $locus_count = keys %$queries_by_locus;
			$modify = "GROUP BY $view.id HAVING count(DISTINCT($view.id,allele_designations.locus))=$locus_count";
		}
		my @allele_queries = values %$queries_by_locus;
		my $combined_allele_queries =
		    "$view.id IN (select distinct($view.id) FROM $view JOIN allele_designations ON $view.id="
		  . "allele_designations.isolate_id WHERE @allele_queries $modify)";
		push @designation_queries, "$combined_allele_queries";
	}
	local $" = $andor;
	push @designation_queries, "@null_queries"    if @null_queries;
	push @designation_queries, "@$scheme_queries" if @$scheme_queries;
	push @designation_queries, "@$cgroup_queries" if @$cgroup_queries;
	return $qry if !@designation_queries;
	if ( $qry =~ /\(\)$/x ) {
		$qry = "SELECT * FROM $view WHERE (@designation_queries)";
	} else {
		$qry .= " AND (@designation_queries)";
	}
	return $qry;
}

sub _get_allele_designations {
	my ( $self, $errors_ref, $andor ) = @_;
	my $q       = $self->{'cgi'};
	my $pattern = LOCUS_PATTERN;
	my ( %lqry, @lqry_blank );
	my $view = $self->{'system'}->{'view'};
	my %combo;
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("designation_value$i") && $q->param("designation_value$i") ne '' ) {
			if ( $q->param("designation_field$i") =~ /$pattern/x ) {
				my $locus      = $1;
				my $locus_info = $self->{'datastore'}->get_locus_info($locus);
				if ( !$locus_info ) {
					push @$errors_ref, 'Invalid locus selected.';
					next;
				}
				my $unmodified_locus = $locus;
				$locus =~ s/'/\\'/gx;
				my $operator = $q->param("designation_operator$i") // '=';
				my $text = $q->param("designation_value$i");
				next if $combo{"$locus\_$operator\_$text"};    #prevent duplicates
				$combo{"$locus\_$operator\_$text"} = 1;
				$self->process_value( \$text );

				if (   lc($text) ne 'null'
					&& ( $locus_info->{'allele_id_format'} eq 'integer' )
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @$errors_ref, "$unmodified_locus is an integer field.";
					next;
				} elsif ( !$self->is_valid_operator($operator) ) {
					push @$errors_ref, "$operator is not a valid operator.";
					next;
				}
				my %methods = (
					'NOT' => sub {
						$lqry{$locus} .= $andor if $lqry{$locus};
						$lqry{$locus} .= (
							( lc($text) eq 'null' )
							? "(EXISTS (SELECT 1 WHERE allele_designations.locus=E'$locus'))"
							: "(allele_designations.locus=E'$locus' AND NOT upper(allele_designations.allele_id)="
							  . "upper(E'$text'))"
						);
					},
					'contains' => sub {
						$lqry{$locus} .= $andor if $lqry{$locus};
						$lqry{$locus} .=
						    "(allele_designations.locus=E'$locus' AND upper(allele_designations.allele_id) "
						  . "LIKE upper(E'\%$text\%'))";
					},
					'starts with' => sub {
						$lqry{$locus} .= $andor if $lqry{$locus};
						$lqry{$locus} .=
						    "(allele_designations.locus=E'$locus' AND upper(allele_designations.allele_id) "
						  . "LIKE upper(E'$text\%'))";
					},
					'ends with' => sub {
						$lqry{$locus} .= $andor if $lqry{$locus};
						$lqry{$locus} .=
						    "(allele_designations.locus=E'$locus' AND upper(allele_designations.allele_id) "
						  . "LIKE upper(E'\%$text'))";
					},
					'NOT contain' => sub {
						$lqry{$locus} .= $andor if $lqry{$locus};
						$lqry{$locus} .=
						    "(allele_designations.locus=E'$locus' AND NOT upper(allele_designations.allele_id) "
						  . "LIKE upper(E'\%$text\%'))";
					},
					'=' => sub {
						if ( lc($text) eq 'null' ) {
							push @lqry_blank,
							  '(NOT EXISTS (SELECT 1 FROM allele_designations WHERE allele_designations.isolate_id='
							  . "$view.id AND locus=E'$locus'))";
						} else {
							$lqry{$locus} .= $andor if $lqry{$locus};
							$lqry{$locus} .=
							  $locus_info->{'allele_id_format'} eq 'text'
							  ? "(allele_designations.locus=E'$locus' AND upper(allele_designations.allele_id)="
							  . "upper(E'$text'))"
							  : "(allele_designations.locus=E'$locus' AND allele_designations.allele_id = E'$text')";
						}
					}
				);
				if ( $methods{$operator} ) {
					$methods{$operator}->();
				} else {
					if ( lc($text) eq 'null' ) {
						push @$errors_ref, "$operator is not a valid operator for comparing null values.";
						next;
					}
					$lqry{$locus} .= $andor if $lqry{$locus};
					if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
						$lqry{$locus} .= "(allele_designations.locus=E'$locus' AND "
						  . "CAST(allele_designations.allele_id AS int) $operator E'$text')";
					} else {
						$lqry{$locus} .= "(allele_designations.locus=E'$locus' AND "
						  . "allele_designations.allele_id $operator E'$text')";
					}
				}
			}
		}
	}
	return ( \%lqry, \@lqry_blank );
}

sub _get_scheme_designations {
	my ( $self, $errors_ref ) = @_;
	my $q = $self->{'cgi'};
	my ( @sqry, @sqry_blank );
	my $view = $self->{'system'}->{'view'};
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("designation_value$i") && $q->param("designation_value$i") ne '' ) {
			if ( $q->param("designation_field$i") =~ /^s_(\d+)_(.*)/x ) {
				my ( $scheme_id, $field ) = ( $1, $2 );
				my $operator          = $q->param("designation_operator$i") // '=';
				my $text              = $q->param("designation_value$i");
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				if ( !$scheme_field_info ) {
					push @$errors_ref, 'Invalid scheme field selected.';
					next;
				}
				my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
				$self->process_value( \$text );
				if (   lc($text) ne 'null'
					&& ( $scheme_field_info->{'type'} eq 'integer' )
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @$errors_ref, "$field is an integer field.";
					next;
				} elsif ( !$self->is_valid_operator($operator) ) {
					push @$errors_ref, "$operator is not a valid operator.";
					next;
				}
				my $isolate_scheme_field_view =
				  $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				$field = "$isolate_scheme_field_view.$field";
				my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
				my $temp_qry    = "SELECT $isolate_scheme_field_view.id FROM $isolate_scheme_field_view";
				$text =~ s/'/\\'/gx;
				my %methods = (
					'NOT' => sub {
						if ( lc($text) eq 'null' ) {
							push @sqry,
							  "($view.id NOT IN ($temp_qry WHERE $field IS NULL) AND $view.id IN ($temp_qry))";
						} else {
							push @sqry,
							  $scheme_field_info->{'type'} eq 'integer'
							  ? "($view.id NOT IN ($temp_qry WHERE CAST($field AS text)= E'$text' AND "
							  . "$view.id IN ($temp_qry)))"
							  : "($view.id NOT IN ($temp_qry WHERE upper($field)=upper(E'$text') AND "
							  . "$view.id IN ($temp_qry)))";
						}
					},
					'contains' => sub {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'integer'
						  ? "($view.id IN ($temp_qry WHERE CAST($field AS text) ~* E'$text'))"
						  : "($view.id IN ($temp_qry WHERE $field ~* E'$text'))";
					},
					'starts with' => sub {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'integer'
						  ? "($view.id IN ($temp_qry WHERE CAST($field AS text) LIKE E'$text\%'))"
						  : "($view.id IN ($temp_qry WHERE $field ILIKE E'$text\%'))";
					},
					'ends with' => sub {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'integer'
						  ? "($view.id IN ($temp_qry WHERE CAST($field AS text) LIKE E'\%$text'))"
						  : "($view.id IN ($temp_qry WHERE $field ILIKE E'\%$text'))";
					},
					'NOT contain' => sub {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'integer'
						  ? "($view.id IN ($temp_qry WHERE CAST($field AS text) !~* E'$text'))"
						  : "($view.id IN ($temp_qry WHERE $field !~* E'$text'))";
					},
					'=' => sub {
						if ( lc($text) eq 'null' ) {
							push @sqry_blank,
							  "($view.id IN ($temp_qry WHERE $field IS NULL) OR $view.id NOT IN ($temp_qry))";
						} else {
							push @sqry,
							  $scheme_field_info->{'type'} eq 'text'
							  ? "($view.id IN ($temp_qry WHERE upper($field)=upper(E'$text')))"
							  : "($view.id IN ($temp_qry WHERE $field=E'$text'))";
						}
					}
				);
				if ( $methods{$operator} ) {
					$methods{$operator}->();
				} else {
					if ( lc($text) eq 'null' ) {
						push @$errors_ref, "$operator is not a valid operator for comparing null values.";
						next;
					}
					if ( $scheme_field_info->{'type'} eq 'integer' ) {
						push @sqry, "($view.id IN ($temp_qry WHERE CAST($field AS int) $operator E'$text'))";
					} else {
						push @sqry, "($view.id IN ($temp_qry WHERE $field $operator E'$text'))";
					}
				}
			}
		}
	}
	return ( \@sqry, \@sqry_blank );
}

#This is just for querying group ids
sub _get_classification_group_designations {
	my ( $self, $errors_ref ) = @_;
	my $q = $self->{'cgi'};
	my ( @qry, @null_qry );
	my $view = $self->{'system'}->{'view'};
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("designation_value$i") && $q->param("designation_value$i") ne '' ) {
			if ( $q->param("designation_field$i") =~ /^cg_(\d+)_group/x ) {
				my ( $cscheme_id, $field ) = ( $1, $2 );
				my $operator     = $q->param("designation_operator$i") // '=';
				my $text         = $q->param("designation_value$i");
				my $cscheme_info = $self->{'datastore'}->get_classification_scheme_info($cscheme_id);
				if ( !$cscheme_info ) {
					push @$errors_ref, 'Invalid classification group scheme selected.';
					next;
				}
				my $scheme_info =
				  $self->{'datastore'}->get_scheme_info( $cscheme_info->{'scheme_id'}, { get_pk => 1 } );
				my $pk = $scheme_info->{'primary_key'};
				$self->process_value( \$text );
				if ( lc($text) ne 'null' && !BIGSdb::Utils::is_int($text) ) {
					push @$errors_ref, "$field is an integer field.";
					next;
				} elsif ( !$self->is_valid_operator($operator) ) {
					push @$errors_ref, "$operator is not a valid operator.";
					next;
				}
				my $cscheme_table = $self->{'datastore'}->create_temp_cscheme_table($cscheme_id);
				my $isolate_scheme_field_view =
				  $self->{'datastore'}->create_temp_isolate_scheme_fields_view( $cscheme_info->{'scheme_id'} );
				my $temp_qry = "SELECT $isolate_scheme_field_view.id FROM $isolate_scheme_field_view";
				$text =~ s/'/\\'/gx;
				my %methods = (
					'NOT' => sub {
						if ( lc($text) eq 'null' ) {
							push @qry, "($view.id IN ($temp_qry WHERE $pk IN (SELECT profile_id FROM $cscheme_table)))";
						} else {
							push @qry,
							  "($view.id IN ($temp_qry WHERE $pk NOT IN (SELECT profile_id "
							  . "FROM $cscheme_table WHERE group_id=$text)))";
						}
					},
					'contains' => sub {
						push @qry,
						  "($view.id IN ($temp_qry WHERE $pk IN (SELECT profile_id "
						  . "FROM $cscheme_table WHERE CAST(group_id AS text) ~ '$text')))";
					},
					'starts with' => sub {
						push @qry,
						  "($view.id IN ($temp_qry WHERE $pk IN (SELECT profile_id "
						  . "FROM $cscheme_table WHERE CAST(group_id AS text) LIKE '$text\%')))";
					},
					'ends with' => sub {
						push @qry,
						  "($view.id IN ($temp_qry WHERE $pk IN (SELECT profile_id "
						  . "FROM $cscheme_table WHERE CAST(group_id AS text) LIKE '\%$text')))";
					},
					'NOT contain' => sub {
						push @qry,
						  "($view.id IN ($temp_qry WHERE $pk IN (SELECT profile_id "
						  . "FROM $cscheme_table WHERE CAST(group_id AS text) !~ '$text')))";
					},
					'=' => sub {
						if ( lc($text) eq 'null' ) {
							push @null_qry,
							  "($view.id IN ($temp_qry WHERE $pk NOT IN (SELECT profile_id FROM $cscheme_table)) OR "
							  . "$view.id NOT IN (SELECT id FROM $isolate_scheme_field_view))";
						} else {
							push @qry,
							  "($view.id IN ($temp_qry WHERE $pk IN (SELECT profile_id "
							  . "FROM $cscheme_table WHERE group_id=$text)))";
						}
					}
				);
				if ( $methods{$operator} ) {
					$methods{$operator}->();
				} else {
					if ( lc($text) eq 'null' ) {
						push @$errors_ref, "$operator is not a valid operator for comparing null values.";
						next;
					}
					push @qry,
					  "($view.id IN ($temp_qry WHERE $pk IN (SELECT profile_id "
					  . "FROM $cscheme_table WHERE group_id $operator $text)))";
				}
			}
		}
	}
	return ( \@qry, \@null_qry );
}

sub _modify_query_for_tags {
	my ( $self, $qry, $errors_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my @tag_queries;
	my $pattern    = LOCUS_PATTERN;
	my $set_id     = $self->get_set_id;
	my $set_clause = $self->_get_set_locus_clause( { prepend => 'AND' } );
	foreach my $i ( 1 .. MAX_ROWS ) {

		if ( ( $q->param("tag_field$i") // '' ) ne '' && ( $q->param("tag_value$i") // '' ) ne '' ) {
			my $action = $q->param("tag_value$i");
			my $locus;
			if ( $q->param("tag_field$i") ne 'any locus' ) {
				if ( $q->param("tag_field$i") =~ /$pattern/x ) {
					$locus = $1;
				}
				if ( !$self->{'datastore'}->is_locus($locus) ) {
					push @$errors_ref, 'Invalid locus selected.';
					next;
				}
			} else {
				$locus = 'any locus';
			}
			$locus =~ s/'/\\'/gx;
			my $temp_qry;
			my $locus_clause =
			  $locus eq 'any locus' ? "(locus IS NOT NULL $set_clause)" : "(locus=E'$locus' $set_clause)";
			my %methods = (
				untagged => "$view.id NOT IN (SELECT DISTINCT isolate_id FROM allele_sequences WHERE $locus_clause)",
				tagged   => "$view.id IN (SELECT isolate_id FROM allele_sequences WHERE $locus_clause)",
				complete => "$view.id IN (SELECT isolate_id FROM allele_sequences WHERE $locus_clause AND complete)",
				incomplete =>
				  "$view.id IN (SELECT isolate_id FROM allele_sequences WHERE $locus_clause AND NOT complete)"
			);
			if ( $methods{$action} ) {
				$temp_qry = $methods{$action};
			} elsif ( $action =~ /^flagged:\ ([\w\s:]+)$/x ) {
				my $flag = $1;
				my $flag_joined_table =
				  'sequence_flags LEFT JOIN allele_sequences ON sequence_flags.id = allele_sequences.id';
				if ( $flag eq 'any' ) {
					$temp_qry = "$view.id IN (SELECT allele_sequences.isolate_id FROM "
					  . "$flag_joined_table WHERE $locus_clause)";
				} elsif ( $flag eq 'none' ) {
					if ( $locus eq 'any locus' ) {
						push @$errors_ref,
						  'Searching for any locus not flagged is not supported. Choose a specific locus.';
					} else {
						$temp_qry = "$view.id IN (SELECT isolate_id FROM allele_sequences WHERE $locus_clause) "
						  . "AND $view.id NOT IN (SELECT isolate_id FROM $flag_joined_table WHERE $locus_clause)";
					}
				} else {
					$temp_qry = "$view.id IN (SELECT allele_sequences.isolate_id FROM $flag_joined_table "
					  . "WHERE $locus_clause AND flag='$flag')";
				}
			}
			push @tag_queries, $temp_qry if $temp_qry;
		}
	}
	if (@tag_queries) {
		my $andor = ( any { $q->param('tag_andor') eq $_ } qw (AND OR) ) ? $q->param('tag_andor') : '';
		local $" = " $andor ";
		if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
			$qry .= " AND (@tag_queries)";
		} else {
			$qry = "SELECT * FROM $view WHERE (@tag_queries)";
		}
	}
	return $qry;
}

sub _modify_query_for_counts {
	my ( $self, $qry, $errors_ref, $args ) = @_;
	my ( $table, $param_prefix, $andor_param, $total_label, $field_label, $field_plural ) =
	  @{$args}{qw(table param_prefix andor_param total_label field_label field_plural)};
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my @count_queries;
	my $pattern = LOCUS_PATTERN;
	my $set_clause = $self->_get_set_locus_clause( { prepend => 'AND' } );
  ROW: foreach my $i ( 1 .. MAX_ROWS ) {

		foreach my $param (qw(field operator value)) {
			next ROW if !defined $q->param("${param_prefix}_$param$i");
			next ROW if $q->param("${param_prefix}_$param$i") eq q();
		}
		my $action = $q->param("${param_prefix}_field$i");
		my %valid_non_locus = map { $_ => 1 } ( 'any locus', $total_label );
		my $locus;
		if ( !$valid_non_locus{ $q->param("${param_prefix}_field$i") } ) {
			if ( $q->param("${param_prefix}_field$i") =~ /$pattern/x ) {
				$locus = $1;
			}
			if ( !$self->{'datastore'}->is_locus($locus) ) {
				push @$errors_ref, 'Invalid locus selected.';
				next;
			}
		} else {
			$locus = $q->param("${param_prefix}_field$i");
		}
		my $count = $q->param("${param_prefix}_value$i");
		if ( !BIGSdb::Utils::is_int($count) || $count < 0 ) {
			push @$errors_ref, "$field_label value must be 0 or a positive integer.";
			next;
		}
		my $operator = $q->param("${param_prefix}_operator$i");
		my $err = $self->_invalid_count( $operator, $count );
		if ($err) {
			push @$errors_ref, $err;
			next;
		}
		$locus =~ s/'/\\'/gx;
		my $search_for_zero = $self->_searching_for_zero( $operator, $count );
		if ( $locus eq $total_label ) {
			my $search_for_zero_qry;
			if ($set_clause) {
				$search_for_zero_qry =
				    "$view.id IN (SELECT id FROM $view WHERE NOT EXISTS(SELECT 1 FROM "
				  . "$table WHERE isolate_id=$view.id$set_clause)) OR $view.id IN (SELECT id FROM "
				  . "$view WHERE NOT EXISTS(SELECT 1 FROM $table WHERE isolate_id=$view.id))";
			} else {
				$search_for_zero_qry = "$view.id IN (SELECT id FROM $view WHERE NOT EXISTS(SELECT 1 FROM "
				  . "$table WHERE isolate_id=$view.id))";
			}
			if ($search_for_zero) {
				push @count_queries, $search_for_zero_qry;
			} else {
				my $temp_qry = "EXISTS (SELECT isolate_id FROM $table WHERE isolate_id=$view.id "
				  . "$set_clause GROUP BY isolate_id HAVING COUNT(isolate_id)$operator$count)";
				if ( $operator eq '<' ) {
					$temp_qry .= " OR $search_for_zero_qry";
				}
				push @count_queries, $temp_qry;
			}
		} elsif ( $locus eq 'any locus' ) {
			if ($search_for_zero) {
				push @$errors_ref, qq(Searching for zero $field_plural of 'any locus' is not supported.);
				next;
			}
			if ( $operator eq '<' ) {
				push @$errors_ref, qq(Searching for fewer than a specified number of $field_plural of )
				  . q('any locus' is not supported.);
				next;
			}
			push @count_queries, "EXISTS (SELECT isolate_id FROM $table WHERE isolate_id=$view.id$set_clause "
			  . "GROUP BY isolate_id,locus HAVING COUNT(*)$operator$count)";
		} else {
			my $search_for_zero_qry = "$view.id IN (SELECT id FROM $view WHERE NOT EXISTS(SELECT 1 "
			  . "FROM $table WHERE isolate_id=$view.id AND locus=E'$locus'))";
			if ($search_for_zero) {
				push @count_queries, $search_for_zero_qry;
			} else {
				my $temp_qry = "$view.id IN (SELECT isolate_id FROM $table WHERE locus=E'$locus' "
				  . "GROUP BY isolate_id HAVING COUNT(*)$operator$count)";
				if ( $operator eq '<' ) {
					$temp_qry .= " OR $search_for_zero_qry";
				}
				push @count_queries, $temp_qry;
			}
		}
	}
	if (@count_queries) {
		my $andor = ( any { $q->param($andor_param) eq $_ } qw (AND OR) ) ? $q->param($andor_param) : '';
		local $" = ") $andor (";
		if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
			$qry .= " AND ((@count_queries))";
		} else {
			$qry = "SELECT * FROM $view WHERE ((@count_queries))";
		}
	}
	return $qry;
}

sub _modify_query_for_designation_counts {
	my ( $self, $qry, $errors_ref ) = @_;
	return $self->_modify_query_for_counts(
		$qry,
		$errors_ref,
		{
			field_plural => 'designations',
			table        => 'allele_designations',
			param_prefix => 'allele_count',
			andor_param  => 'count_andor',
			total_label  => 'total designations',
			field_label  => 'Allele count'
		}
	);
}

sub _modify_query_for_tag_counts {
	my ( $self, $qry, $errors_ref ) = @_;
	return $self->_modify_query_for_counts(
		$qry,
		$errors_ref,
		{
			field_plural => 'tags',
			table        => 'allele_sequences',
			param_prefix => 'tag_count',
			andor_param  => 'tag_count_andor',
			total_label  => 'total tags',
			field_label  => 'Tag count'
		}
	);
}

sub _get_set_locus_clause {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $set_id = $self->get_set_id;
	my $clause =
	  $set_id
	  ? ' (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	$clause = " $options->{'prepend'}$clause" if $clause && $options->{'prepend'};
	return $clause;
}

sub _searching_for_zero {
	my ( $self, $operator, $value ) = @_;
	my $search_for_zero = ( ( $operator eq '=' && $value == 0 ) || ( $operator eq '<' && $value == 1 ) ) ? 1 : 0;
	return $search_for_zero;
}

sub _invalid_count {
	my ( $self, $operator, $value ) = @_;
	my %valid_operator = map { $_ => 1 } ( '=', '<', '>' );
	if ( !$valid_operator{$operator} ) {
		return "$operator is not a valid operator.";
	}
	if ( $operator eq '<' && $value == 0 ) {
		return 'It is meaningless to search for count < 0.';
	}
	return;
}

sub _modify_query_for_designation_status {
	my ( $self, $qry, $errors_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my @status_queries;
	my $pattern = LOCUS_PATTERN;
	my $set_clause = $self->_get_set_locus_clause( { prepend => 'AND' } );
	foreach my $i ( 1 .. MAX_ROWS ) {
		if (   defined $q->param("allele_status_field$i")
			&& $q->param("allele_status_field$i") ne ''
			&& defined $q->param("allele_status_value$i")
			&& $q->param("allele_status_value$i") ne '' )
		{
			my $action = $q->param("allele_status_field$i");
			my $locus;
			if ( $q->param("allele_status_field$i") ne 'any locus' ) {
				if ( $q->param("allele_status_field$i") =~ /$pattern/x ) {
					$locus = $1;
				}
				if ( !$self->{'datastore'}->is_locus($locus) ) {
					push @$errors_ref, 'Invalid locus selected.';
					next;
				}
			} else {
				$locus = 'any locus';
			}
			my $status = $q->param("allele_status_value$i");
			if ( none { $status eq $_ } qw (provisional confirmed) ) {
				push @$errors_ref, 'Invalid status selected.';
				next;
			}
			$locus =~ s/'/\\'/gx;
			my $locus_clause = $locus eq 'any locus' ? '' : "allele_designations.locus=E'$locus' AND ";
			push @status_queries, "$view.id IN (SELECT isolate_id FROM allele_designations WHERE "
			  . "(${locus_clause}status='$status'$set_clause))";
		}
	}
	if (@status_queries) {
		my $andor = ( any { $q->param('status_andor') eq $_ } qw (AND OR) ) ? $q->param('status_andor') : '';
		local $" = " $andor ";
		if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
			$qry .= " AND (@status_queries)";
		} else {
			$qry = "SELECT * FROM $view WHERE (@status_queries)";
		}
	}
	return $qry;
}

sub _should_display_fieldset {
	my ( $self, $fieldset ) = @_;
	my %fields = (
		provenance          => 'provenance',
		phenotypic          => 'phenotypic',
		allele_designations => 'loci',
		allele_count        => 'allele_count',
		allele_status       => 'allele_status',
		tag_count           => 'tag_count',
		tags                => 'tags'
	);
	return if !$fields{$fieldset};
	if ( $self->{'prefs'}->{"${fieldset}_fieldset"} || $self->_highest_entered_fields( $fields{$fieldset} ) ) {
		return 1;
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $phenotypic_fieldset_display = $self->_should_display_fieldset('phenotypic') ? 'inline' : 'none';
	my $allele_designations_fieldset_display =
	  $self->_should_display_fieldset('allele_designations') ? 'inline' : 'none';
	my $allele_count_fieldset_display  = $self->_should_display_fieldset('allele_count')  ? 'inline' : 'none';
	my $allele_status_fieldset_display = $self->_should_display_fieldset('allele_status') ? 'inline' : 'none';
	my $tag_count_fieldset_display     = $self->_should_display_fieldset('tag_count')     ? 'inline' : 'none';
	my $tags_fieldset_display          = $self->_should_display_fieldset('tags')          ? 'inline' : 'none';
	my $filters_fieldset_display       = $self->{'prefs'}->{'filters_fieldset'}
	  || $self->filters_selected ? 'inline' : 'none';
	my $buffer   = $self->SUPER::get_javascript;
	my $panel_js = $self->get_javascript_panel(
		qw(provenance phenotypic allele_designations allele_count allele_status
		  tag_count tags list filters)
	);
	my $ajax_load = q(var script_path = $(location).attr('href');script_path = script_path.split('?')[0];)
	  . q(var fieldset_url=script_path + '?db=' + $.urlParam('db') + '&page=query&no_header=1';);
	my %fields = (
		phenotypic          => 'phenotypic',
		allele_designations => 'loci',
		allele_count        => 'allele_count',
		allele_status       => 'allele_status',
		tag_count           => 'tag_count',
		tags                => 'tags'
	);
	foreach my $fieldset ( keys %fields ) {
		if ( !$self->_highest_entered_fields( $fields{$fieldset} ) ) {
			$ajax_load .=
			    qq(if (\$('fieldset#${fieldset}_fieldset').length){\n)
			  . qq(\$('fieldset#${fieldset}_fieldset div').)
			  . q(html('<span class="fas fa-spinner fa-spin fa-lg fa-fw"></span> Loading ...').)
			  . qq(load(fieldset_url + '&fieldset=$fieldset')};);
		}
	}
	if ( !$q->param('list') ) {
		$ajax_load .=
		    qq(if (\$('fieldset#list_fieldset').length){\n)
		  . q($('fieldset#list_fieldset div').)
		  . q(html('<span class="fas fa-spinner fa-spin fa-lg fa-fw"></span> Loading ...').)
		  . q(load(fieldset_url + '&fieldset=list')};);
	}
	$buffer .= << "END";
\$(function () {
  	\$('#query_modifier').css({display:"block"});
  	\$('#phenotypic_fieldset').css({display:"$phenotypic_fieldset_display"});
   	\$('#allele_designations_fieldset').css({display:"$allele_designations_fieldset_display"});
   	\$('#allele_count_fieldset').css({display:"$allele_count_fieldset_display"});
   	\$('#allele_status_fieldset').css({display:"$allele_status_fieldset_display"});
   	\$('#tag_count_fieldset').css({display:"$tag_count_fieldset_display"});
   	\$('#tags_fieldset').css({display:"$tags_fieldset_display"});
   	\$('#filters_fieldset').css({display:"$filters_fieldset_display"});
 	setTooltips();
 	\$('.multiselect').multiselect().multiselectfilter();
$panel_js
	$ajax_load
	\$(document).ajaxComplete(function() {
        setTooltips();
        initiate_autocomplete();
        \$('.ajax_script').each(function (index, element) { eval(element.innerHTML); })
	});
	\$('.ajax_script').each(function (index, element) { eval(element.innerHTML); })
	
	\$("#bookmark_trigger,#close_bookmark").click(function(){		
		\$("#bookmark_panel").toggle("slide",{direction:"right"},"fast");
		\$("#bookmark_trigger").show();		
		return false;
	});
	\$("#bookmark_trigger").show();
 });
 
function setTooltips() {
	\$('#prov_tooltip,#phenotypic_tooltip,#loci_tooltip').tooltip({ content: "<h3>Search values</h3><p>Empty field "
  		+ "values can be searched using the term 'null'. </p><h3>Number of fields</h3><p>Add more "
  	    + "fields by clicking the '+' button."
  		+ "</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, "
  		+ "'OR' to match ANY of these terms.</p>" });
  	\$('#tag_tooltip,#tag_count_tooltip,#allele_count_tooltip,#allele_status_tooltip').tooltip({ content: "<h3>Number of "
  		+ "fields</h3><p>Add more fields by clicking the '+' button.</p>" });	
}
 
function loadContent(url) {
	var row = parseInt(url.match(/row=(\\d+)/)[1]);
	var fields = url.match(/fields=([provenance|phenotypic|loci|allele_count|allele_status|table_fields|tag_count|tags]+)/)[1];
	if (fields == 'provenance'){			
		add_rows(url,fields,'fields',row,'prov_field_heading','add_fields');
	} else if (fields == 'phenotypic'){
		add_rows(url,fields,'phenotypic',row,'phenotypic_field_heading','add_phenotypic_fields');	
	} else if (fields == 'loci'){
		add_rows(url,fields,'locus',row,'loci_field_heading','add_loci');
	} else if (fields == 'allele_count'){
		add_rows(url,fields,'allele_count',row,'allele_count_field_heading','add_allele_count');	
	} else if (fields == 'allele_status'){
		add_rows(url,fields,'allele_status',row,'allele_status_field_heading','add_allele_status');		
	} else if (fields == 'table_fields'){
		add_rows(url,fields,'table_field',row,'table_field_heading','add_table_fields');
	} else if (fields == 'tag_count'){
		add_rows(url,fields,'tag_count',row,'tag_count_heading','add_tag_count');			
	} else if (fields == 'tags'){
		add_rows(url,fields,'tag',row,'locus_tags_heading','add_tags');
	}
}

function refresh_filters(){
	var list_values = [];
	var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query&no_header=1&fieldset=filters";
	\$("fieldset#filters_fieldset select[id\$='_list']").each(function (index){
		list_values[\$(this).attr('id')] =  \$(this).val();
	});
	\$("fieldset#filters_fieldset div")
	.load(url, function(){
			
		reloadTooltips();
		for (key in list_values){
			\$("#" + key).val(list_values[key]);				
		}
		\$('.multiselect').multiselect().multiselectfilter();
	});
}
END
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my $autocomplete_js;
	if (@$fields) {
		my $first = 1;
		foreach my $field (@$fields) {
			my $options = $self->{'xmlHandler'}->get_field_option_list($field);
			if (@$options) {
				$autocomplete_js .= ",\n" if !$first;
				$autocomplete_js .= "       f_$field: [\n";
				my %used;
				foreach my $value (@$options) {
					next if $used{$value};
					( my $display_value = $value ) =~ s/"/\\"/gx;
					$autocomplete_js .= qq(       "$display_value");
					$autocomplete_js .= ',' if $value ne $options->[-1];
					$autocomplete_js .= "\n";
					$used{$value} = 1;
				}
				$autocomplete_js .= '       ]';
				$first = 0;
			}
		}
		my $ext_att = $self->get_extended_attributes;
		foreach my $field ( keys %$ext_att ) {
			foreach my $attribute ( @{ $ext_att->{$field} } ) {
				$autocomplete_js .= ",\n" if !$first;
				$autocomplete_js .= qq(       "e_$field||$attribute": [\n);
				my $values = $self->{'datastore'}->run_query(
					'SELECT DISTINCT value FROM isolate_value_extended_attributes WHERE '
					  . '(isolate_field,attribute)=(?,?) ORDER BY value',
					[ $field, $attribute ],
					{ fetch => 'col_arrayref', cache => 'IsolateQuery::extended_attribute_values' }
				);
				foreach my $value (@$values) {
					$value =~ s/"/\\"/gx;
					$autocomplete_js .= qq(       "$value");
					$autocomplete_js .= ',' if $value ne $values->[-1];
					$autocomplete_js .= "\n";
				}
				$autocomplete_js .= '       ]';
				$first = 0;
			}
		}
		my $eav_fields = $self->{'datastore'}->get_eav_fields;
		foreach my $eav_field (@$eav_fields) {
			if ( $eav_field->{'option_list'} ) {
				$autocomplete_js .= ",\n" if !$first;
				$autocomplete_js .= "       eav_$eav_field->{'field'}: [\n";
				my @options = split /\s*;\s*/x, $eav_field->{'option_list'};
				foreach my $value (@options) {
					$value =~ s/"/\\"/gx;
					$autocomplete_js .= qq(       "$value");
					$autocomplete_js .= ',' if $value ne $options[-1];
					$autocomplete_js .= "\n";
				}
				$autocomplete_js .= '       ]';
				$first = 0;
			}
		}
	}
	if ($autocomplete_js) {
		$buffer .= << "END";
var fieldLists = {
  	$autocomplete_js
};		
\$(function() {	
	initiate_autocomplete();
});
function initiate_autocomplete() {
	\$("#provenance").on("change", "[name^='prov_field']", function () {
		set_autocomplete_values(\$(this));
	});
	\$("[name^='prov_field']").each(function (i){
		set_autocomplete_values(\$(this));
	});
	\$("#phenotypic").on("change", "[name^='phenotypic_field']", function () {
		set_autocomplete_values(\$(this));
	});
	\$("[name^='phenotypic_field']").each(function (i){
		set_autocomplete_values(\$(this));
	});	
}

function set_autocomplete_values(element){
	var valueField = element.attr('name').replace("field","value");		
	if (!fieldLists[element.val()]){
		\$('#' + valueField).autocomplete({ disabled: true });
	} else {
		\$('#' + valueField).autocomplete({
			disabled: false,
 			source: fieldLists[element.val()]
		});
	}		
}
END
	}
	return $buffer;
}

sub _get_select_items {
	my ($self) = @_;
	my ( $field_list, $labels ) =
	  $self->get_field_selection_list( { isolate_fields => 1, sender_attributes => 1, extended_attributes => 1 } );
	my $grouped = $self->{'xmlHandler'}->get_grouped_fields;
	my @grouped_fields;
	foreach (@$grouped) {
		push @grouped_fields, "f_$_";
		( $labels->{"f_$_"} = $_ ) =~ tr/_/ /;
	}
	my @select_items;
	foreach my $field (@$field_list) {
		push @select_items, $field;
		if ( $field eq "f_$self->{'system'}->{'labelfield'}" ) {
			push @select_items, @grouped_fields;
		}
	}
	return \@select_items, $labels;
}

sub _highest_entered_fields {
	my ( $self, $type ) = @_;
	my %param_name = (
		provenance    => 'prov_value',
		phenotypic    => 'phenotypic_value',
		loci          => 'designation_value',
		allele_count  => 'allele_count_value',
		allele_status => 'allele_status_value',
		tag_count     => 'tag_count_value',
		tags          => 'tag_value'
	);
	my $q = $self->{'cgi'};
	my $highest;
	for my $row ( 1 .. MAX_ROWS ) {
		my $param = "$param_name{$type}$row";
		$highest = $row
		  if defined $q->param($param) && $q->param($param) ne '';
	}
	return $highest;
}

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->SUPER::initiate;
	$self->{$_} = 1 foreach qw(noCache addProjects addBookmarks);
	if ( !$self->{'cgi'}->param('save_options') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		foreach my $attribute (
			qw (phenotypic allele_designations allele_count allele_status
			tag_count tags list filters)
		  )
		{
			my $value =
			  $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, "${attribute}_fieldset" );
			$self->{'prefs'}->{"${attribute}_fieldset"} = ( $value // '' ) eq 'on' ? 1 : 0;
		}
		my $value = $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'provenance_fieldset' );
		$self->{'prefs'}->{'provenance_fieldset'} = ( $value // '' ) eq 'off' ? 0 : 1;
	}
	if ( BIGSdb::Utils::is_int( scalar $q->param('bookmark') ) ) {
		$self->_initiate_bookmark( scalar $q->param('bookmark') );
	}
	$self->set_level1_breadcrumbs;
	return;
}

sub _initiate_bookmark {
	my ( $self, $bookmark_id ) = @_;
	my $bookmark =
	  $self->{'datastore'}->run_query( 'SELECT * FROM bookmarks WHERE id=?', $bookmark_id, { fetch => 'row_hashref' } );
	return if !$bookmark;
	if ( !$bookmark->{'public'} ) {
		return if !$self->{'username'};
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		return if !$user_info;
		return if $bookmark->{'user_id'} != $user_info->{'id'};
	}
	my $q      = $self->{'cgi'};
	my $params = decode_json( $bookmark->{'params'} );
	foreach my $param ( keys %$params ) {
		$q->param( $param => $params->{$param} );
		if ( $param =~ /(.+)_list$/x ) {
			$self->{'temp_prefs'}->{'dropdownfields'}->{$1} = 1;
		}
	}
	my $show_sets = ( $self->{'system'}->{'sets'} // q() ) eq 'yes' && !defined $self->{'system'}->{'set_id'} ? 1 : 0;
	if ($show_sets) {
		$q->param( set_id => $bookmark->{'set_id'} );
	}
	$q->param( submit => 1 );
	return;
}
1;
