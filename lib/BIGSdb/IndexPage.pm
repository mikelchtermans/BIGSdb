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
package BIGSdb::IndexPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::StatusPage);
use BIGSdb::Constants qw(:interface :design :login_requirements);
use BIGSdb::Utils;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->{$_} = 1 foreach qw(jQuery cookieconsent noCache);
	$self->choose_set;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $set_id = $self->get_set_id;
		my $scheme_data = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id } );
		$self->{'tooltips'} = 1 if @$scheme_data > 1;
	}
	return;
}

sub print_content {
	my ($self)      = @_;
	my $script_name = $self->{'system'}->{'script_name'};
	my $q           = $self->{'cgi'};
	my $desc        = $self->get_db_description;
	my $max_width = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $index_panel_max_width = $max_width - 300;
	my $title_max_width = $max_width - 15;
	say q(<div class="flex_container" style="flex-direction:column;align-items:center">);
	say q(<div>);
	say qq(<div style="width:95vw;max-width:${title_max_width}px"></div>);
	say qq(<div id="title_container" style="max-width:${title_max_width}px">);
	say qq(<h1>$desc database</h1>);
	$self->print_banner;

	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		$self->print_set_section;
	}
	say q(</div>);
	say qq(<div id="main_container" class="flex_container" style="max-width:${max_width}px">);
	say qq(<div class="index_panel" style="max-width:${index_panel_max_width}px">);
	$self->_print_main_section;
	say q(</div>);
	say q(<div class="menu_panel">);
	$self->_print_main_menu;
	say q(</div>);
	say q(</div>);
	say q(</div>);
	say q(</div>);
	return;
}

sub _print_main_menu {
	my ($self) = @_;
	$self->_print_login_menu_item;
	$self->_print_submissions_menu_item;
	$self->_print_private_data_menu_item;
	$self->_print_projects_menu_item;
	$self->_print_downloads_menu_item;
	$self->_print_plugin_menu_items;
	$self->_print_options_menu_item;
	$self->_print_info_menu_item;
	$self->_print_related_database_menu_item;
	return;
}

sub _print_plugin_menu_items {
	my ($self)       = @_;
	my $cache_string = $self->get_cache_string;
	my $url_root     = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}$cache_string&amp;";
	$self->_print_plugin_menu_item(
		{
			sections => [qw(export)],
			label    => 'EXPORT',
			icon     => 'fas fa-external-link-alt',
			href     => "${url_root}page=pluginSummary&amp;category=export"
		}
	);
	$self->_print_plugin_menu_item(
		{
			sections => [qw(breakdown analysis third_party)],
			label    => 'ANALYSIS',
			icon     => 'fas fa-chart-line',
			href     => "${url_root}page=pluginSummary&amp;category=analysis"
		}
	);
	return;
}

sub _print_downloads_menu_item {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	my $cache_string = $self->get_cache_string;
	my $url_root     = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}$cache_string&amp;";
	$self->_print_menu_item(
		{
			icon  => 'fas fa-download',
			label => 'DOWNLOADS',
			href  => "${url_root}page=downloads"
		}
	);
	return;
}

sub _print_login_menu_item {
	my ($self) = @_;
	my $login_requirement = $self->{'datastore'}->get_login_requirement;
	return if $login_requirement == NOT_ALLOWED && !$self->{'needs_authentication'};
	my $user_info       = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $q               = $self->{'cgi'};
	my $page            = $q->param('page');
	my $instance_clause = $self->{'instance'} ? qq(db=$self->{'instance'}&amp;) : q();
	if ( !$user_info && !$self->{'username'} && $login_requirement == OPTIONAL && $page ne 'login' ) {
		$self->_print_menu_item(
			{
				icon  => 'fas fa-sign-in-alt',
				label => 'LOG IN',
				href  => "$self->{'system'}->{'script_name'}?${instance_clause}page=login",
				class => 'menu_item_login'
			}
		);
	}
	if ( ( $self->{'system'}->{'authentication'} // q() ) eq 'builtin' && $self->{'username'} ) {
		$self->_print_menu_item(
			{
				icon  => 'fas fa-sign-out-alt',
				label => 'LOG OUT',
				href  => "$self->{'system'}->{'script_name'}?${instance_clause}page=logout",
				class => 'menu_item_login',
				links => [
					{
						href => "$self->{'system'}->{'script_name'}?${instance_clause}page=changePassword",
						text => 'Change password'
					}
				]
			}
		);
	}
	return;
}

sub _print_plugin_menu_item {
	my ( $self, $args ) = @_;
	my ( $label, $icon, $href, $list_number ) = @{$args}{qw (label icon href list_number)};
	$list_number //= 3;
	my $cache_string = $self->get_cache_string;
	my $url_root     = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}$cache_string&amp;";
	my $set_id       = $self->get_set_id;
	local $" = q(|);
	my $sections = qq(@{$args->{'sections'}});
	my $plugins  = $self->{'pluginManager'}
	  ->get_appropriate_plugin_names( $sections, $self->{'system'}->{'dbtype'}, undef, { set_id => $set_id } );

	if ( @$plugins <= $list_number ) {
		my $links = [];
		my $scheme_data = $self->get_scheme_data( { with_pk => 1 } );
		foreach my $plugin (@$plugins) {
			my $att      = $self->{'pluginManager'}->get_plugin_attributes($plugin);
			my $menuitem = $att->{'menutext'};
			my $scheme_arg =
			  (      $self->{'system'}->{'dbtype'} eq 'sequences'
				  && $att->{'seqdb_type'} eq 'schemes'
				  && @$scheme_data == 1 )
			  ? qq(&amp;scheme_id=$scheme_data->[0]->{'id'})
			  : q();
			push @$links,
			  {
				href => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=plugin&amp;name=$att->{'module'}$scheme_arg$cache_string),
				text => $menuitem
			  };
		}
		$self->_print_menu_item(
			{
				icon  => $icon,
				label => $label,
				links => $links,
				href  => $href
			}
		);
	} elsif (@$plugins) {
		$self->_print_menu_item(
			{
				icon  => $icon,
				label => $label,
				href  => $href
			}
		);
	}
	return;
}

sub _print_menu_item {
	my ( $self, $values ) = @_;
	my ( $links, $icon, $added_class, $href, $label ) = @{$values}{qw(links icon class href label )};
	( my $id = $label ) =~ s/\s/_/gx;
	if ( !$links ) {
		my $class = 'menu_item';
		$class .= qq( $added_class) if $added_class;
		say qq(<a href="$href">);
		say qq(<div class="$class">);
		if ($icon) {
			say qq(<span class="$icon fa-fw fa-pull-left"></span>);
		}
		say $label;
		say q(</div></a>);
	} else {
		my $class = $added_class ? qq( $added_class) : q();
		say q(<div class="multi_menu_item">);
		if ($href) {
			say qq(<a href="$href">);
		}
		say qq(<div class="multi_menu_link$class">);
		if ($icon) {
			say qq(<span class="$icon fa-fw fa-pull-left"></span>);
		}
		say $label;
		say q(</div>);
		if ($href) {
			say q(</a>);
		}
		say qq(<div id="${id}_trigger" class="multi_menu_trigger$class">);
		say q(<span class="fas fa-plus"></span>);
		say q(</div>);
		say q(</div>);
		$class .= q(_panel) if $class;
		say qq(<div id="${id}_panel" class="multi_menu_panel$class">);
		say q(<ul>);

		foreach my $link (@$links) {
			say qq(<li><a href="$link->{'href'}">$link->{'text'}</a></li>);
		}
		say q(</ul>);
		say q(</div>);
	}
	return;
}

sub _print_jobs {
	my ($self) = @_;
	return if !$self->{'system'}->{'read_access'} eq 'public' || !$self->{'config'}->{'jobs_db'};
	return if !defined $self->{'username'};
	my $days = $self->{'config'}->{'results_deleted_days'} // 7;
	my $jobs = $self->{'jobManager'}->get_user_jobs( $self->{'instance'}, $self->{'username'}, $days );
	return if !@$jobs;
	my %status_counts;
	$status_counts{ $_->{'status'} }++ foreach @$jobs;
	my $days_plural = $days == 1  ? '' : 's';
	my $jobs_plural = @$jobs == 1 ? '' : 's';
	say q(<div class="box" id="jobs">);
	say q(<span class="job_icon fas fa-briefcase fa-3x fa-pull-left"></span>);
	say q(<h2>Jobs</h2>);
	say q(<p>You have submitted or run )
	  . @$jobs
	  . qq( offline job$jobs_plural in the past )
	  . ( $days_plural ? $days : '' )
	  . qq( day$days_plural. )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=jobs">Show jobs</a></p>);
	my %replace = ( started => 'running', submitted => 'queued' );
	my @breakdown;

	foreach my $status (qw (started submitted finished failed cancelled terminated)) {
		push @breakdown, ( $replace{$status} // $status ) . ": $status_counts{$status}" if $status_counts{$status};
	}
	local $" = '; ';
	say qq(<p>@breakdown</p>);
	say q(</div>);
	return;
}

sub get_javascript {
	my ($self) = @_;
	return <<"JS";
\$(document).ready(function()   { 
	\$('.multi_menu_trigger').on('click', function(){
		var trigger_id = this.id;	
		var panel_id = trigger_id.replace('_trigger','_panel');
	  	if (\$("#" + panel_id).css('display') == 'none') {
	  		\$("#" + panel_id).slideDown();
	  		\$("#" + trigger_id).html('<span class="fas fa-minus"></span>');
	    } else {
	  	    \$("#" + panel_id).slideUp();
	  	    \$("#" + trigger_id).html('<span class="fas fa-plus"></span>');
	    }  
	});	
}); 


JS
}

sub _print_main_section {
	my ($self) = @_;

	#Append to URLs to ensure unique caching.
	my $cache_string = $self->get_cache_string;
	my $set_id       = $self->get_set_id;
	my $url_root     = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}$cache_string&amp;";
	say q(<h2 style="text-align:center">Query database</h2>);
	say qq(<div class="flex_container index_panel_$self->{'system'}->{'dbtype'}">);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_print_large_button_link(
			{
				title => 'Search database',
				href  => "${url_root}page=query",
				text  => 'Browse, search by any criteria, or enter list of attributes.'
			}
		);
		my $loci = $self->{'datastore'}->get_loci( { set_id => $set_id, do_not_order => 1 } );
		if (@$loci) {
			$self->_print_large_button_link(
				{
					title => 'Search by combinations of loci',
					href  => "${url_root}page=profiles",
					text  => 'This can include partial matches to find related isolates.'
				}
			);
		}
		if ( $self->{'username'} ) {
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $bookmarks = $self->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM bookmarks WHERE user_id=?)', $user_info->{'id'} );
			if ($bookmarks) {
				$self->_print_large_button_link(
					{
						title => 'Bookmarks',
						href  => "${url_root}page=bookmarks",
						text  => 'Retrieve dataset from bookmarked queries.'
					}
				);
			}
		}
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$self->_print_large_button_link(
			{
				title => 'Sequence query',
				href  => "${url_root}page=sequenceQuery",
				text  => 'Query a single sequence or whole genome assembly to identify allelic matches.'
			}
		);
		$self->_print_large_button_link(
			{
				title => 'Batch sequence query',
				href  => "${url_root}page=batchSequenceQuery",
				text  => 'Query multiple independent sequences in FASTA format to identify allelic matches.'
			}
		);
		$self->_print_large_button_link(
			{
				title => 'Sequence attribute search',
				href  => "${url_root}page=sequences",
				text  => 'Find alleles by matching criteria (all loci together)'
			}
		);
		$self->_print_large_button_link(
			{
				title => 'Locus-specific sequence attribute search',
				href  => "${url_root}page=alleleQuery",
				text  => 'Select, analyse and download specific alleles from a single locus.'
			}
		);
		my $scheme_data = $self->get_scheme_data( { with_pk => 1 } );
		if (@$scheme_data) {
			my $scheme_arg = @$scheme_data == 1 ? "&amp;scheme_id=$scheme_data->[0]->{'id'}" : '';
			my $scheme_desc = @$scheme_data == 1 ? $scheme_data->[0]->{'name'} : '';
			$self->_print_large_button_link(
				{
					title => 'Allelic profile query',
					href  => "${url_root}page=query$scheme_arg",
					text  => "Search, browse or enter list of $scheme_desc profiles"
				}
			);
			$self->_print_large_button_link(
				{
					title => "Search by combinations of $scheme_desc alleles",
					href  => "${url_root}page=profiles$scheme_arg",
					text  => 'This can include partial matches to find related profiles.'
				}
			);
			$self->_print_large_button_link(
				{
					title => 'Batch profile query',
					href  => "${url_root}page=batchProfiles$scheme_arg",
					text  => "Lookup $scheme_desc multiple allelic profiles together."
				}
			);
		}
	}
	say q(</div>);
	return;
}

sub _print_large_button_link {
	my ( $self, $values ) = @_;
	say q(<div class="link_box">);
	say qq(<h3><a href="$values->{'href'}">$values->{'title'}</a></h3>);
	say $values->{'text'};
	say q(</div>);
	return;
}

sub _get_label {
	my ( $self, $number ) = @_;
	return $number if $number < 100;
	return qq(<span style="font-size:0.8em">$number</span>) if $number < 1000;
	my $label = int( $number / 1000 );
	$label = 9 if $label > 9;
	return qq(<span style="font-size:0.8em">${label}K+</span>);
}

sub _print_download_section {
	my ( $self, $scheme_data ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
	my $q                   = $self->{'cgi'};
	my $seq_download_buffer = '';
	my $scheme_buffer       = '';
	my $group_count         = $self->{'datastore'}->run_query('SELECT COUNT(*) FROM scheme_groups');
	if ( !( $self->{'system'}->{'disable_seq_downloads'} && $self->{'system'}->{'disable_seq_downloads'} eq 'yes' )
		|| $self->is_admin )
	{
		$seq_download_buffer =
		    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles)
		  . ( $group_count ? '&amp;tree=1' : '' )
		  . qq(">Allele sequences</a></li>\n);
	}
	my $first = 1;
	my $i     = 0;
	if ( @$scheme_data > 1 ) {
		$scheme_buffer .= q(<li style="white-space:nowrap">);
		$scheme_buffer .= $q->start_form;
		$scheme_buffer .= $q->popup_menu( -name => 'scheme_id', -values => $scheme_ids_ref, -labels => $desc_ref );
		$scheme_buffer .= $q->hidden('db');
		my $download = DOWNLOAD;
		$scheme_buffer .= q( <button type="submit" name="page" value="downloadProfiles" )
		  . qq(class="smallbutton">$download Profiles</button>\n);
		$scheme_buffer .= $q->end_form;
		$scheme_buffer .= q(</li>);
	} elsif ( @$scheme_data == 1 ) {
		$scheme_buffer .=
		    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=downloadProfiles&amp;scheme_id=$scheme_data->[0]->{'id'}">)
		  . qq($scheme_data->[0]->{'name'} profiles</a></li>);
	}
	if ( $seq_download_buffer || $scheme_buffer ) {
		say q(<div style="float:left; margin-right:1em" class="grid-item">);
		say q(<span class="main_icon fas fa-download fa-3x fa-pull-left"></span>);
		say q(<h2>Downloads</h2>);
		say q(<ul class="toplevel">);
		say $seq_download_buffer;
		say $scheme_buffer;
		say q(</ul></div>);
	}
	return;
}

sub _print_options_menu_item {
	my ($self)       = @_;
	my $cache_string = $self->get_cache_string;
	my $links        = [
		{
			href => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=options$cache_string",
			text => 'General options'
		}
	];
	my $url_root = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$links,
		  {
			href => "${url_root}table=loci$cache_string",
			text => 'Locus display'
		  };
		push @$links,
		  {
			href => "${url_root}table=schemes$cache_string",
			text => 'Scheme display'
		  };
		push @$links,
		  {
			href => "${url_root}table=scheme_fields$cache_string",
			text => 'Scheme field display'
		  };
	} else {
		push @$links,
		  {
			href => "${url_root}table=schemes$cache_string",
			text => 'Scheme options'
		  };
	}
	if ( $self->{'system'}->{'authentication'} eq 'builtin' && $self->{'auth_db'} && $self->{'username'} ) {
		my $user_db_name = $self->{'datastore'}->run_query(
			'SELECT user_dbases.dbase_name FROM user_dbases JOIN users '
			  . 'ON user_dbases.id=users.user_db WHERE users.user_name=?',
			$self->{'username'}
		);
		$user_db_name //= $self->{'system'}->{'db'};
		my $clients_authorized = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM access_tokens WHERE (dbase,username)=(?,?))',
			[ $user_db_name, $self->{'username'} ],
			{ db => $self->{'auth_db'} }
		);
		if ($clients_authorized) {
			push @$links,
			  {
				href =>
				  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=authorizeClient&amp;modify=1",
				text => 'View/modify client software permissions'
			  };
		}
	}
	$self->_print_menu_item(
		{
			icon  => 'fas fa-cog',
			label => 'CUSTOMISE',
			links => $links,
		}
	);
	return;
}

sub _print_submissions_menu_item {
	my ($self) = @_;
	return
	  if $self->{'config'}->{'disable_updates'}
	  || ( $self->{'system'}->{'disable_updates'} // q() ) eq 'yes';
	return if ( $self->{'system'}->{'submissions'} // '' ) ne 'yes';
	if ( !$self->{'config'}->{'submission_dir'} ) {
		$logger->error('Submission directory is not configured in bigsdb.conf.');
		return;
	}
	my $set_id = $self->get_set_id // 0;
	my $set_string =
	  ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ? qq(&amp;choose_set=1&amp;sets_list=$set_id) : q();
	my $pending_submissions = $self->_get_pending_submission_count;
	my $number_icon         = q();
	if ($pending_submissions) {
		$pending_submissions = '99+' if $pending_submissions > 99;
		$number_icon .= q(<span class="fa-stack" style="font-size:0.7em;margin:-0.5em 0 -0.2em 0.5em">);
		$number_icon .= q(<span class="fas fa-circle fa-stack-2x" style="color:#d44"></span>);
		$number_icon .= qq(<span class="fa fa-stack-1x fa-stack-text">$pending_submissions</span>);
		$number_icon .= q(</span>);
	}
	$self->_print_menu_item(
		{
			icon  => 'fas fa-upload',
			label => "SUBMISSIONS $number_icon",
			href  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit$set_string"
		}
	);
	return;
}

sub _print_projects_menu_item {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $cache_string = $self->get_cache_string;
	my $url_root     = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}$cache_string&amp;";
	my $listed_projects =
	  $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM projects WHERE list AND NOT private)');
	my $links = [];
	if ($listed_projects) {
		push @$links,
		  {
			href => "${url_root}page=projects",
			text => 'Public projects'
		  };
	}
	if ( $self->show_user_projects ) {
		push @$links,
		  {
			href => "${url_root}page=userProjects",
			text => 'Your projects'
		  };
	}
	return if !@$links;
	if ( @$links == 1 ) {
		$self->_print_menu_item(
			{
				icon  => 'fas fa-list-alt',
				label => uc( $links->[0]->{'text'} ),
				href  => $links->[0]->{'href'}
			}
		);
	} else {
		$self->_print_menu_item(
			{
				icon  => 'fas fa-list-alt',
				label => 'PROJECTS',
				links => $links
			}
		);
	}
	return;
}

sub _print_private_data_menu_item {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	return if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !$user_info;
	return if $user_info->{'status'} eq 'user' || !$self->can_modify_table('isolates');
	my $limit                         = $self->{'datastore'}->get_user_private_isolate_limit( $user_info->{'id'} );
	my $is_member_of_no_quota_project = $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM merged_project_users m JOIN projects p '
		  . 'ON m.project_id=p.id WHERE user_id=? AND modify)',
		$user_info->{'id'}
	);
	return if !$limit && !$is_member_of_no_quota_project;
	my $total_private = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM private_isolates pi WHERE user_id=? AND EXISTS(SELECT 1 '
		  . "FROM $self->{'system'}->{'view'} v WHERE v.id=pi.isolate_id)",
		$user_info->{'id'}
	);
	my $cache_string = $self->get_cache_string;
	my $number_icon  = q();

	if ($total_private) {
		my $label = $self->_get_label($total_private);
		$number_icon .= q(<span class="fa-stack" style="font-size:0.7em;margin:-0.5em 0 -0.2em 0.5em">);
		$number_icon .= q(<span class="fas fa-circle fa-stack-2x" style="color:#484"></span>);
		$number_icon .= qq(<span class="fa fa-stack-1x fa-stack-text">$label</span>);
	}
	$self->_print_menu_item(
		{
			icon  => 'fas fa-lock',
			label => "PRIVATE DATA $number_icon",
			href  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}$cache_string&amp;page=privateRecords"
		}
	);
	return;
}

sub _print_info_menu_item {
	my ($self)       = @_;
	my $cache_string = $self->get_cache_string;
	my $links        = [
		{
			href => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=version",
			text => 'About BIGSdb'
		},
		{
			href => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=status$cache_string",
			text => 'Database status'
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $plugins = $self->{'pluginManager'}->get_installed_plugins;
		if ( $plugins->{'DatabaseFields'} ) {
			push @$links,
			  {
				href =>
				  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=DatabaseFields",
				text => 'Description of database fields'
			  };
		}
	}
	$self->_print_menu_item(
		{
			icon  => 'fas fa-info-circle',
			label => 'INFORMATION',
			links => $links
		}
	);
	return;
}

sub _print_related_database_menu_item {
	my ($self) = @_;
	return if !$self->{'system'}->{'related_databases'};
	my @dbases = split /;/x, $self->{'system'}->{'related_databases'};
	return if !@dbases;
	my $links = [];
	foreach my $dbase (@dbases) {
		my ( $config, $name ) = split /\|/x, $dbase;
		push @$links,
		  {
			href => "$self->{'system'}->{'script_name'}?db=$config",
			text => $name
		  };
	}
	if ( @$links > 1 ) {
		$self->_print_menu_item(
			{
				icon  => 'fas fa-database',
				label => 'DATABASES',
				links => $links
			}
		);
	} else {
		$self->_print_menu_item(
			{
				icon  => 'fas fa-database',
				label => uc( $links->[0]->{'text'} ),
				href  => $links->[0]->{'href'}
			}
		);
	}
	return;
}

sub _get_pending_submission_count {
	my ($self) = @_;
	return 0 if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return 0 if $user_info->{'status'} ne 'admin' && $user_info->{'status'} ne 'curator';
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		return 0 if !$self->can_modify_table('isolates');
		my $count = $self->{'datastore'}
		  ->run_query( 'SELECT COUNT(*) FROM submissions WHERE (type,status)=(?,?)', [ 'isolates', 'pending' ] );
		if ( $self->can_modify_table('sequence_bin') ) {
			$count +=
			  $self->{'datastore'}
			  ->run_query( 'SELECT COUNT(*) FROM submissions WHERE (type,status)=(?,?)', [ 'genomes', 'pending' ] );
		}
		return $count;
	} else {
		my $count = 0;
		my $allele_submissions =
		  $self->{'datastore'}->run_query(
			'SELECT a.locus FROM submissions s JOIN allele_submissions a ON s.id=a.submission_id WHERE s.status=?',
			'pending', { fetch => 'col_arrayref' } );
		foreach my $locus (@$allele_submissions) {
			if (   $self->is_admin
				|| $self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $user_info->{'id'} ) )
			{
				$count++;
			}
		}
		my $profile_submissions = $self->{'datastore'}->run_query(
			'SELECT ps.scheme_id FROM submissions s JOIN profile_submissions ps '
			  . 'ON s.id=ps.submission_id WHERE s.status=?',
			'pending',
			{ fetch => 'col_arrayref' }
		);
		foreach my $scheme_id (@$profile_submissions) {
			if ( $self->is_admin || $self->{'datastore'}->is_scheme_curator( $scheme_id, $user_info->{'id'} ) ) {
				$count++;
			}
		}
		return $count;
	}
}

sub _print_plugin_section {
	my ($self) = @_;
	my $scheme_data = $self->get_scheme_data( { with_pk => 1 } );
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
	my $q            = $self->{'cgi'};
	my $set_id       = $self->get_set_id;
	my $cache_string = $self->get_cache_string;
	my @sections     = qw(breakdown export analysis third_party miscellaneous);
	my %names        = (
		breakdown     => 'Breakdown',
		export        => 'Export',
		analysis      => 'Analysis',
		third_party   => 'Third party tools',
		miscellaneous => 'Miscellaneous'
	);
	local $" = q(|);
	my $plugins = $self->{'pluginManager'}
	  ->get_appropriate_plugin_names( "@sections", $self->{'system'}->{'dbtype'}, undef, { set_id => $set_id } );

	if (@$plugins) {
		say q(<div class="box" id="plugins"><div class="scrollable"><div class="grid">);
		my %icon = (
			breakdown     => 'fas fa-chart-pie',
			export        => 'far fa-save',
			analysis      => 'fas fa-chart-line',
			third_party   => 'fas fa-external-link-alt',
			miscellaneous => 'far fa-file-alt'
		);
		foreach my $section (@sections) {
			$q->param( 'page', 'index' );
			$plugins =
			  $self->{'pluginManager'}
			  ->get_appropriate_plugin_names( $section, $self->{'system'}->{'dbtype'}, undef, { set_id => $set_id } );
			next if !@$plugins;
			say q(<div style="float:left; margin-right:1em" class="grid-item">);
			say qq(<span class="plugin_icon $icon{$section} fa-3x fa-pull-left"></span>);
			say qq(<h2 style="margin-right:1em">$names{$section}</h2><ul class="toplevel">);
			foreach my $plugin (@$plugins) {
				my $att      = $self->{'pluginManager'}->get_plugin_attributes($plugin);
				my $menuitem = $att->{'menutext'};
				my $scheme_arg =
				  (      $self->{'system'}->{'dbtype'} eq 'sequences'
					  && $att->{'seqdb_type'} eq 'schemes'
					  && @$scheme_data == 1 )
				  ? qq(&amp;scheme_id=$scheme_data->[0]->{'id'})
				  : q();
				say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=plugin&amp;name=$att->{'module'}$scheme_arg$cache_string">$menuitem</a>);
				say qq( - $att->{'menu_description'}) if $att->{'menu_description'};
				say q(</li>);
			}
			say q(</ul></div>);
		}
		say q(</div></div></div>);
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return $desc;
}
1;
