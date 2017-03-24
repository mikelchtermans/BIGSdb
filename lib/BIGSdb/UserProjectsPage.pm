#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
package BIGSdb::UserProjectsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(uniq);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return "User projects - $desc";
}

sub _user_projects_enabled {
	my ($self) = @_;
	if (
		(
			( ( $self->{'system'}->{'public_login'} // q() ) ne 'no' )
			|| $self->{'system'}->{'read_access'} ne 'public'
		)
		&& ( $self->{'system'}->{'user_projects'} // q() ) eq 'yes'
	  )
	{
		return 1;
	}
	return;
}

sub print_content {
	my ($self) = @_;
	say q(<h1>User projects</h1>);
	if ( !$self->_user_projects_enabled ) {
		say q(<div class="box" id="statusbad">User projects are not enabled in this database.</p></div>);
		return;
	}
	my $q = $self->{'cgi'};
	$self->_add_new_project if $q->param('new_project');
	$self->_delete_project  if $q->param('delete');
	if ( $q->param('edit') ) {
		$self->_edit_members;
		return;
	}
	if ( $q->param('modify_users') ) {
		$self->_modify_users;
		return;
	}
	$self->_print_user_projects;
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery jQuery.multiselect noCache);
	return;
}

sub _delete_project {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $project_id = $q->param('project_id');
	return if !BIGSdb::Utils::is_int($project_id);
	return if $self->_fails_admin_check($project_id);
	my $isolates =
	  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM project_members WHERE project_id=?', $project_id );
	if ($isolates) {
		if ( $q->param('confirm') ) {
			$self->_actually_delete_project($project_id);
		} else {
			my $plural       = $isolates > 1 ? q(s) : q();
			my $button_class = RESET_BUTTON_CLASS;
			my $delete       = DELETE;
			say qq(<div class="box" id="restricted"><p>This project contains $isolates isolate$plural. Please )
			  . q(confirm that you wish to remove the project (the isolates in the project will not be deleted).</p>)
			  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=userProjects&amp;delete=1&amp;project_id=$project_id&amp;confirm=1" )
			  . qq(class="$button_class ui-button-text-only"><span class="ui-button-text">)
			  . qq($delete Delete project</span></a></p></div>);
		}
	} else {
		$self->_actually_delete_project($project_id);
	}
	return;
}

sub _actually_delete_project {
	my ( $self, $project_id ) = @_;
	eval { $self->{'db'}->do( 'DELETE FROM projects WHERE id=?', undef, $project_id ); };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		say q(<div class="box" id="statusbad"><p>Cannot delete project.</p></div>);
	}
	$self->{'db'}->commit;
	return;
}

sub _fails_project_check {
	my ( $self, $project_id ) = @_;
	if ( !BIGSdb::Utils::is_int($project_id) ) {
		say q(<div class="box" id="statusbad"><p>No valid project id passed.</p></div>);
		return 1;
	}
	return;
}

sub _fails_admin_check {
	my ( $self, $project_id ) = @_;
	if ( !$self->_is_project_admin($project_id) ) {
		say q(<div class="box" id="statusbad"><p>You are not an admin for this project.</p></div>);
		return 1;
	}
	return;
}

sub _edit_members {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $project_id = $q->param('project_id');
	return if $self->_fails_project_check($project_id);
	return if $self->_fails_admin_check($project_id);
	my $view        = $self->{'system'}->{'view'};
	my $current_ids = $self->{'datastore'}->run_query(
		"SELECT pm.isolate_id FROM project_members AS pm JOIN $view AS i ON pm.isolate_id=i.id "
		  . 'WHERE pm.project_id=? ORDER BY pm.isolate_id',
		$project_id,
		{ fetch => 'col_arrayref' }
	);
	if ( $q->param('update') ) {
		my $new_ids = [];
		my @invalid;
		my @no_isolate;
		my @ids = split /\n/x, $q->param('ids');
		my $valid_ids = $self->{'datastore'}->run_query( "SELECT id FROM $view", undef, { fetch => 'col_arrayref' } );
		my %valid_ids = map { $_ => 1 } @$valid_ids;
		foreach my $id (@ids) {
			$id =~ s/^\s+|\s+$//gx;
			next if !$id;
			if ( !BIGSdb::Utils::is_int($id) ) {
				push @invalid, $id;
			} elsif ( !$valid_ids{$id} ) {
				push @no_isolate, $id;
			} else {
				push @$new_ids, $id;
			}
		}
		local $" = q(, );
		my @errors;
		if (@invalid) {
			push @errors, qq(The following ids are not integers: @invalid);
		}
		if (@no_isolate) {
			push @errors, qq(The following ids are not found in the current database view: @no_isolate);
		}
		if (@errors) {
			local $" = q(</p><p>);
			say qq(<div class="box" id="statusbad"><p>Update failed: @errors</p></div>);
		} else {
			$self->_update_project_members( $project_id, $current_ids, $new_ids );
		}
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	my $project = $self->{'datastore'}->run_query( 'SELECT short_description,full_description FROM projects WHERE id=?',
		$project_id, { fetch => 'row_hashref' } );
	say qq(<h2>Project: $project->{'short_description'}</h2>);
	say qq(<p>$project->{'full_description'}</p>) if $project->{'full_description'};
	say q(<p>The list below contains id numbers for isolate records belonging to this project. You can add and remove )
	  . q(records to this project by modifying the list of isolate ids. This only affects which records belong to the )
	  . q(project - you will not remove isolate records from the database by removing them from this list.</p>);
	say q(<fieldset style="float:left"><legend>Isolate ids</legend>);
	local $" = qq(\n);
	say $q->start_form;
	say $q->textarea( -name => 'ids', -rows => 10, -cols => 8, -default => qq(@$current_ids) );
	say q(</fieldset>);
	$self->print_action_fieldset( { submit_label => 'Update', project_id => $project_id, edit => 1 } );
	$q->param( update => 1 );
	say $q->hidden($_) foreach qw(db page project_id edit update);
	say $q->end_form;
	say q(</div>);
	say q(<p>You can also add isolate records to this project from the results of a )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query">query</a>.</p>);
	say q(</div>);
	return;
}

sub _update_project_members {
	my ( $self, $project_id, $current_ids, $new_ids ) = @_;
	my %new = map { $_ => 1 } @$new_ids;
	my %old = map { $_ => 1 } @$current_ids;
	my $add = [];
	my $remove = [];
	foreach my $new_id (@$new_ids) {
		next if $old{$new_id};
		push @$add, $new_id;
	}
	foreach my $old_id (@$current_ids) {
		next if $new{$old_id};
		push @$remove, $old_id;
	}
	local $" = q(, );
	my @results;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );

	#Populate temp tables with new and old to do batch add and remove with a single call.
	if (@$add) {
		my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $add );
		eval {
			$self->{'db'}->do( 'INSERT INTO project_members (project_id,isolate_id,curator,datestamp) '
				  . "SELECT $project_id,value,$user_info->{'id'},'now' FROM $temp_table" );
		};
		if ($@) {
			$logger->error($@);
			say q(<div class="box" id="statusbad"><p>Adding ids to project failed.</p></div>);
			$self->{'db'}->rollback;
			return;
		}
		my $count = @$add;
		my $plural = $count == 1 ? q() : q(s);
		push @results, qq($count record$plural added.);
	}
	if (@$remove) {
		my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $remove );
		eval {
			$self->{'db'}->do(
				'DELETE FROM project_members WHERE project_id=? AND isolate_id IN ' . "(SELECT value FROM $temp_table)",
				undef, $project_id
			);
		};
		if ($@) {
			$logger->error($@);
			say q(<div class="box" id="statusbad"><p>Removing ids from project failed.</p></div>);
			$self->{'db'}->rollback;
			return;
		}
		my $count = @$remove;
		my $plural = $count == 1 ? q() : q(s);
		push @results, qq($count record$plural removed.);
	}
	$self->{'db'}->commit;
	if ( @$add || @$remove ) {
		local $" = q(</p><p>);
		say qq(<div class="box" id="resultsheader"><p>@results</p></div>);
	} else {
		say q(<div class="box" id="resultsheader"><p>No changes made.</p></div>);
	}
	return;
}

sub _get_project_user_groups {
	my ( $self, $project_id ) = @_;
	return $self->{'datastore'}->run_query(
		'SELECT pug.user_group FROM project_user_groups AS pug JOIN user_groups AS ug ON '
		  . 'pug.user_group=ug.id WHERE pug.project_id=? ORDER BY UPPER(ug.description)',
		$project_id,
		{ fetch => 'col_arrayref', cache => 'UserProjectsPage::get_project_user_groups' }
	);
}

sub _modify_users {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $project_id = $q->param('project_id');
	return if $self->_fails_project_check($project_id);
	return if $self->_fails_admin_check($project_id);
	my $user_info   = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $user_groups = $self->{'datastore'}->run_query(
		'SELECT ug.id,ug.description FROM user_group_members AS ugm JOIN user_groups ug ON '
		  . 'ugm.user_group=ug.id WHERE user_id=? ORDER BY UPPER(ug.description)',
		$user_info->{'id'},
		{ fetch => 'all_arrayref', slice => {} }
	);
	$self->_update_user_groups($project_id) if $q->param('update_user_groups');
	say q(<div class="box" id="resultstable">);
	my $project = $self->_get_project($project_id);
	say qq(<p><strong>Project: $project->{'short_description'}</strong></p>);

	if (@$user_groups) {
		$self->_print_user_group_form( $project_id, $user_groups );
	}
	$self->_print_user_form($project_id);
	say q(</div>);
	return;
}

sub _print_user_group_form {
	my ( $self, $project_id, $user_groups ) = @_;
	my $user_group_members = $self->_get_project_user_groups($project_id);
	my $q                  = $self->{'cgi'};
	my $ids                = [];
	my $labels             = {};
	foreach my $ug (@$user_groups) {
		push @$ids, $ug->{'id'};
		$labels->{ $ug->{'id'} } = $ug->{'description'};
	}
	say q(<h2>User groups</h2>);
	say q(<p>All members of selected user groups can view this project )
	  . q((only user groups that you are a member of are shown).</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Select user groups</legend>);
	say q(<p>Select user groups able to access project</p>);
	say $q->scrolling_list(
		-name     => 'user_groups',
		-id       => 'user_groups',
		-values   => $ids,
		-labels   => $labels,
		-default  => $user_group_members,
		-multiple => 'multiple',
		-size     => 4,
		-class    => 'multiselect'
	);
	say q(</fieldset>);

	if (@$user_group_members) {
		say q(<fieldset style="float:left"><legend>User group permissions</legend>);
		say q(<table class="resultstable">);
		say q(<tr><th>User group</th><th>Add/Remove records</th></tr>);
		my $td = 1;
		foreach my $group_id (@$user_group_members) {
			my $group = $self->{'datastore'}->run_query(
				'SELECT ug.description,pug.modify FROM user_groups AS ug JOIN project_user_groups '
				  . 'AS pug ON ug.id=pug.user_group WHERE (pug.project_id,pug.user_group)=(?,?)',
				[ $project_id, $group_id ],
				{ fetch => 'row_hashref' }
			);
			say qq(<tr class="td$td"><td>$group->{'description'}</td><td>);
			say $q->checkbox(
				-name    => "ug_${group_id}_modify",
				-label   => '',
				-checked => $group->{'modify'} ? 'checked' : ''
			);
			say q(</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		say q(</table>);
		say q(</fieldset>);
	}
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Update user groups' } );
	$q->param( update_user_groups => 1 );
	say $q->hidden($_) foreach qw(db page modify_users project_id update_user_groups);
	say $q->end_form;
	return;
}

sub _update_user_groups {
	my ( $self, $project_id ) = @_;
	my $user_info          = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $user_group_members = $self->_get_project_user_groups($project_id);
	my %existing           = map { $_ => 1 } @$user_group_members;
	my $q                  = $self->{'cgi'};
	my @new_groups         = $q->param('user_groups');
	my %new_groups         = map { $_ => 1 } @new_groups;
	eval {
		foreach my $new (@new_groups) {
			my $can_currently_modify =
			  $self->{'datastore'}
			  ->run_query( 'SELECT modify FROM project_user_groups WHERE (project_id,user_group)=(?,?)',
				[ $project_id, $new ] );
			my $modify = $q->param("ug_${new}_modify");
			next if !$existing{$new};
			if ( ( $can_currently_modify && !$modify ) || ( !$can_currently_modify && $q->param("ug_${new}_modify") ) )
			{
				$self->{'db'}->do(
					'UPDATE project_user_groups SET (modify,curator,datestamp)=(?,?,?) '
					  . 'WHERE (project_id,user_group)=(?,?)',
					undef, $modify ? 'true' : 'false', $user_info->{'id'}, 'now', $project_id, $new
				);
			}
		}
		foreach my $new (@new_groups) {
			next if $existing{$new};
			$self->{'db'}->do(
				'INSERT INTO project_user_groups (project_id,user_group,modify,curator,datestamp) VALUES (?,?,?,?,?)',
				undef, $project_id, $new, 'false', $user_info->{'id'}, 'now' );
		}
		foreach my $existing_group (@$user_group_members) {
			next if $new_groups{$existing_group};
			$self->{'db'}->do( 'DELETE FROM project_user_groups WHERE (project_id,user_group)=(?,?)',
				undef, $project_id, $existing_group );
		}
	};
	if ($@) {
		say q(<div class="box" id="statusbad"><p>Cannot update user groups.</p></div>);
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _print_user_form {
	my ( $self, $project_id ) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('remove_user') ) {
		$self->_remove_user( $project_id, $q->param('remove_user') );
	}
	if ( $q->param('update_users') ) {
		$self->_update_users($project_id);
	}
	say q(<h2>Users</h2>);
	my $users = $self->_get_project_users($project_id);
	if ( !@$users ) {
		say q(<p>No users have permission to view this project.</p>);
		return;
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my @user_ids;
	( undef, my $labels ) = $self->{'datastore'}->get_users;
	@$users = sort { $labels->{ $a->{'user_id'} } cmp $labels->{ $b->{'user_id'} } } @$users;
	my $users_not_in_group = $self->{'datastore'}->run_query(
		'SELECT user_id FROM project_users WHERE project_id=? AND user_id NOT IN '
		  . '(SELECT user_id FROM user_group_members WHERE user_group IN '
		  . '(SELECT user_group FROM project_user_groups WHERE project_id=?)) AND user_id!=?',
		[ $project_id, $project_id, $user_info->{'id'} ],
		{ fetch => 'col_arrayref' }
	);
	my %users_not_in_group = map { $_ => 1 } @$users_not_in_group;
	push @user_ids, $_->{'user_id'} foreach @$users;
	say q(<p>The following users have permission to access the project )
	  . q((either explicitly or through membership of a user group).</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Users</legend>);
	say q(<div class="scrollable"><table class="resultstable">);
	say q(<tr>);

	if (@$users_not_in_group) {
		say q(<th>Remove</th>);
	}
	say q(<th>User</th><th>Admin</th><th>Add/Remove records</th></tr>);
	my $td = 1;
	foreach my $user (@$users) {
		my $disabled = $user->{'user_id'} == $user_info->{'id'};
		say qq(<tr class="td$td"><td>);
		if (@$users_not_in_group) {
			if ( $users_not_in_group{ $user->{'user_id'} } ) {
				my $remove = DELETE;
				say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=userProjects&amp;modify_users=1&amp;project_id=$project_id&amp;)
				  . qq(remove_user=$user->{'user_id'}" class="action">$remove</a>);
			}
			say q(</td><td>);
		}
		say qq($labels->{$user->{'user_id'}}</td><td>);
		$q->delete("user_$user->{'user_id'}_admin");
		say $q->checkbox(
			-name    => "user_$user->{'user_id'}_admin",
			-label   => '',
			-checked => $user->{'admin'} ? 'checked' : '',
			$disabled ? ( -disabled => $disabled ) : undef
		);
		say q(</td><td>);
		$user->{'modify'} = 1 if $user->{'admin'};
		$disabled = 1
		  if $user->{'modify'} && $self->_user_in_group_with_modify_permissions( $project_id, $user->{'user_id'} );
		$q->delete("user_$user->{'user_id'}_modify");
		say $q->checkbox(
			-name    => "user_$user->{'user_id'}_modify",
			-label   => '',
			-checked => $user->{'modify'} ? 'checked' : '',
			$disabled ? ( -disabled => $disabled ) : undef
		);
		say q(</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div></fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Update users' } );
	$q->param( update_users => 1 );
	say $q->hidden($_) foreach qw(db page modify_users project_id update_users);
	say $q->end_form;
	return;
}

sub _user_in_group_with_modify_permissions {
	my ( $self, $project_id, $user_id ) = @_;
	return $self->{'datastore'}->run_query(
		'SELECT bool_or(modify) FROM project_user_groups AS pug JOIN user_group_members AS ugm '
		  . 'ON pug.user_group=ugm.user_group WHERE (ugm.user_id,pug.project_id)=(?,?)',
		[ $user_id, $project_id ],
		{ cache => 'UserProjectsPage::user_in_group_with_modify_permissions' }
	);
}

sub _remove_user {
	my ( $self, $project_id, $user_id ) = @_;
	return if $self->_fails_project_check($project_id);
	return if $self->_fails_admin_check($project_id);
	return if !BIGSdb::Utils::is_int($user_id);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if $user_id == $user_info->{'id'};    #Don't remove yourself.
	eval {
		$self->{'db'}->do( 'DELETE FROM project_users WHERE (project_id,user_id)=(?,?)', undef, $project_id, $user_id );
	};

	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	return;
}

sub _update_users {
	my ( $self, $project_id ) = @_;
	return if $self->_fails_project_check($project_id);
	return if $self->_fails_admin_check($project_id);
	my $q         = $self->{'cgi'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $users     = $self->_get_project_users($project_id);
	my $explicit_permissions =
	  $self->{'datastore'}->run_query( 'SELECT user_id,admin,modify FROM project_users WHERE project_id=?',
		$project_id, { fetch => 'all_hashref', key => 'user_id' } );
	eval {
		foreach my $user (@$users) {
			my $user_id = $user->{'user_id'};
			next if $user_id == $user_info->{'id'};
			my ( $modify, $admin ) =
			  ( $q->param("user_${user_id}_modify") ? 1 : 0, $q->param("user_${user_id}_admin") ? 1 : 0 );
			if ( ( $modify || $admin ) && !$explicit_permissions->{$user_id} ) {
				$self->{'db'}->do(
					'INSERT INTO project_users (project_id,user_id,admin,modify,curator,datestamp) '
					  . 'VALUES (?,?,?,?,?,?)',
					undef, $project_id, $user_id, $admin, $modify, $user_info->{'id'}, 'now'
				);
			} else {
				if (   $modify != $explicit_permissions->{$user_id}->{'modify'}
					|| $admin != $explicit_permissions->{$user_id}->{'admin'} )
				{
					$self->{'db'}->do(
						'UPDATE project_users SET (admin,modify,curator,datestamp)=(?,?,?,?) WHERE '
						  . '(project_id,user_id)=(?,?)',
						undef, $admin, $modify, $user_info->{'id'}, 'now', $project_id, $user_id
					);
				}
			}
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _is_project_admin {
	my ( $self, $project_id ) = @_;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM merged_project_users WHERE (project_id,user_id)=(?,?) AND admin)',
		[ $project_id, $user_info->{'id'} ] );
}

sub _add_new_project {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $short_desc = $q->param('short_description');
	return if !$short_desc;
	my $desc_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM projects WHERE short_description=?)', $short_desc );
	if ($desc_exists) {
		say q(<div class="box" id="statusbad"><p>There is already a project defined with this name. )
		  . q(Please choose a different name.</p></div>);
		return;
	}
	my $id        = $self->next_id('projects');
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	eval {
		$self->{'db'}->do(
			'INSERT INTO projects (id,short_description,full_description,isolate_display,'
			  . 'list,private,no_limit,curator,datestamp) VALUES (?,?,?,?,?,?,?,?,?)',
			undef,
			$id,
			$short_desc,
			$q->param('full_description'),
			'false',
			'false',
			'true',
			'false',
			$user_info->{'id'},
			'now'
		);
		$self->{'db'}
		  ->do( 'INSERT INTO project_users (project_id,user_id,admin,modify,curator,datestamp) VALUES (?,?,?,?,?,?)',
			undef, $id, $user_info->{'id'}, 'true', 'true', $user_info->{'id'}, 'now' );
	};
	if ($@) {
		$logger->error($@);
		say q(<div class="box" id="statusbad"><p>Could not add project at this time. Please try again later.</p></div>);
		$self->{'db'}->rollback;
	} else {
		say q(<div class="box" id="resultsheader"></p>Project successfully added.</p></div>);
		$self->{'db'}->commit;
	}
	$q->delete($_) foreach qw(short_description full_description);
	return;
}

sub _print_user_projects {
	my ($self) = @_;
	say q(<div class="box" id="queryform">);
	say q(<h2>New private projects</h2>);
	say q(<p>Projects allow you to group isolates so that you can analyse them easily together.</p>);
	say q(<p>Please enter the details for a new project. The project name needs to be unique on the system. )
	  . q(A description is optional but only projects with descriptions will be displayed on an isolate )
	  . q(record page.</p>);
	say q(<div class="scrollable">);
	my $q = $self->{'cgi'};
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>New project</legend>);
	say q(<ul>);
	say q(<li><label for="short_description" class="form" style="width:6em">Name:</label>);
	say $q->textfield(
		-name      => 'short_description',
		-id        => 'short_description',
		-size      => 30,
		-maxlength => 40,
		-required  => 'required'
	);
	say q(</li><li>);
	say q(<li><label for="full_description" class="form" style="width:6em">Description:</label>);
	say $q->textarea( -name => 'full_description', -id => 'full_description', -cols => 40 );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { submit_label => 'Create', no_reset => 1 } );
	$q->param( new_project => 1 );
	say $q->hidden($_) foreach qw(db page new_project);
	say $q->end_form;
	say q(</div></div>);
	say q(<div class="box" id="resultstable">);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $projects  = $self->{'datastore'}->run_query(
		'SELECT p.id,p.short_description,p.full_description,pu.admin FROM merged_project_users AS pu JOIN projects '
		  . 'AS p ON p.id=pu.project_id WHERE user_id=? ORDER BY UPPER(short_description)',
		$user_info->{'id'},
		{ fetch => 'all_arrayref', slice => {} }
	);

	if (@$projects) {
		my $is_admin = $self->_is_admin_of_any($projects);
		say q(<h2>Your projects</h2>);
		say q(<div class="scrollable"><table class="resultstable">);
		say q(<tr>);
		if ($is_admin) {
			say q(<th>Delete</th><th>Add/remove records</th><th>Modify users</th>);
		}
		say q(<th>Project</th><th>Description</th><th>Administrator</th><th>Isolates</th><th>Browse</th></tr>);
		my $td = 1;
		foreach my $project (@$projects) {
			say $self->_get_project_row( $is_admin, $project, $td );
			$td = $td == 1 ? 2 : 1;
		}
		say q(</table></div>);
		if ($is_admin) {
			say q(<p>You can also add isolates to projects from the results of a )
			  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query">query</a>.</p>);
			say q(Note that deleting a project will not delete its member isolates.</p>);
		}
	} else {
		say q(<h2>Existing projects</h2>);
		say q(<p>You do not own or are a member of any projects.</p>);
	}
	say q(</div>);
	return;
}

sub _get_project {
	my ( $self, $project_id ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT * FROM projects WHERE id=?', $project_id, { fetch => 'row_hashref' } );
}

sub _get_project_users {
	my ( $self, $project_id ) = @_;
	return $self->{'datastore'}->run_query( 'SELECT * FROM merged_project_users WHERE project_id=?',
		$project_id, { fetch => 'all_arrayref', slice => {}, cache => 'UserProjectsPage::get_project_users' } );
}

sub _get_project_row {
	my ( $self, $is_admin, $project, $td ) = @_;
	my $count = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM project_members WHERE project_id=? '
		  . "AND isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})",
		$project->{'id'},
		{ cache => 'UserProjectsPage::isolate_count' }
	);
	my $q      = $self->{'cgi'};
	my $admin  = $project->{'admin'} ? TRUE : FALSE;
	my $buffer = qq(<tr class="td$td">);
	if ($is_admin) {
		if ( $project->{'admin'} ) {
			my ( $delete, $edit, $users ) = ( DELETE, EDIT, USERS );
			$buffer .= qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=userProjects&amp;delete=1&amp;project_id=$project->{'id'}" class="action">$delete</a></td>);
			$buffer .= qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=userProjects&amp;edit=1&amp;project_id=$project->{'id'}" class="action">$edit</a></td>);
			$buffer .=
			    qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=userProjects&amp;modify_users=1&amp;project_id=$project->{'id'}" class="action">)
			  . qq($users</a></td>);
		} else {
			if ($is_admin) {
				$buffer .= q(<td></td><td></td><td></td>);
			}
		}
	}
	$buffer .= qq(<td>$project->{'short_description'}</td>)
	  . qq(<td>$project->{'full_description'}</td><td>$admin</td><td>$count</td><td>);
	$buffer .=
	    qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
	  . qq(project_list=$project->{'id'}&amp;submit=1"><span class="fa fa-binoculars action browse">)
	  . q(</span></a></td></tr>);
	return $buffer;
}

sub _is_admin_of_any {
	my ( $self, $projects ) = @_;
	foreach my $project (@$projects) {
		return 1 if $project->{'admin'};
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	if (! Modernizr.touch){
  	 	\$('.multiselect').multiselect({noneSelectedText:'&nbsp;'});
  	}
});	
END
	return $buffer;
}
1;
