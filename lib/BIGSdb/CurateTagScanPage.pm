#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::CurateTagScanPage;
use strict;
use base qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Time::HiRes qw(gettimeofday);
use List::MoreUtils qw(uniq any none);
use Apache2::Connection ();
use BIGSdb::Page qw(SEQ_METHODS SEQ_FLAGS);

sub get_javascript {
	my $buffer = << "END";
function listbox_selectall(listID, isSelect) {
	\$("#" + listID + " option").attr("selected",isSelect);
}
	
END
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	foreach (qw (tooltips jQuery noCache)) {
		$self->{$_} = 1;
	}
}

sub _print_interface {
	my ( $self, $ids, $labels ) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Sequence tag scan</h1>\n";
	if ( !@$ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>There are no sequences in the sequence bin.</p></div>\n";
		return;
	} elsif ( !$self->can_modify_table('allele_sequences') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to tag sequences.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>Please select the required isolate ids and loci for sequence scanning - use ctrl or shift to make 
	  multiple selections. In addition to selecting individual loci, you can choose to include all loci defined in schemes
	  by selecting the appropriate scheme description. By default, loci are only scanned for an isolate when no allele designation has 
	  been made or sequence tagged. You can choose to rescan loci with existing designations or tags by 
	  selecting the appropriate options.</p>\n";
	my ( $loci, $locus_labels ) = $self->get_field_selection_list( { 'loci' => 1, 'all_loci' => 1, 'sort_labels' => 1 } );
	print $q->start_form;
	print "<div class=\"scrollable\"><fieldset>\n<legend>Isolates</legend>\n";
	print $q->scrolling_list(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => $ids,
		-labels   => $labels,
		-size     => 11,
		-multiple => 'true'
	);
	print
"<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"isolate_id\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"isolate_id\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" /></div>\n";
	print "</fieldset>\n";
	print "<fieldset>\n<legend>Loci</legend>\n";
	print $q->scrolling_list( -name => 'locus', -id => 'locus', -values => $loci, -labels => $locus_labels, -size => 11,
		-multiple => 'true' );
	print
"<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"locus\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"locus\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" /></div>\n";
	print "</fieldset>";
	print "<fieldset>\n<legend>Schemes</legend>\n";
	my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
	my %scheme_desc;

	foreach (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
		$scheme_desc{$_} = $scheme_info->{'description'};
	}
	push @$schemes, 0;
	$scheme_desc{0} = 'No scheme';
	print $q->scrolling_list(
		-name     => 'scheme_id',
		-id       => 'scheme_id',
		-values   => $schemes,
		-labels   => \%scheme_desc,
		-size     => 11,
		-multiple => 'true'
	);
	print
"<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"scheme_id\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"scheme_id\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" /></div>\n";
	print "</fieldset>";
	print "<fieldset>\n<legend>Parameters</legend>\n";
	print "<ul><li><label for =\"identity\" class=\"parameter\">Min % identity:</label>";
	print $q->popup_menu(
		-name    => 'identity',
		-id      => 'identity',
		-values  => [qw(50 55 60 65 70 75 80 85 90 91 92 93 94 95 96 97 98 99 100)],
		-default => 70
	);
	print " <a class=\"tooltip\" title=\"Minimum % identity - Match required for partial matching.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	print "<li><label for =\"alignment\" class=\"parameter\">Min % alignment:</label>";
	print $q->popup_menu(
		-name    => 'alignment',
		-id      => 'alignment',
		-values  => [qw(30 35 40 45 50 55 60 65 70 75 80 85 90 91 92 93 94 95 96 97 98 99 100)],
		-default => 50
	);
	print
" <a class=\"tooltip\" title=\"Minimum % alignment - Percentage of allele sequence length required to be aligned for partial matching.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	print "<li><label for =\"word_size\" class=\"parameter\">BLASTN word size:</label>\n";
	print $q->popup_menu(
		-name    => 'word_size',
		-id      => 'word_size',
		-values  => [qw(7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28)],
		-default => 15
	);
	print
" <a class=\"tooltip\" title=\"BLASTN word size - This is the length of an exact match required to initiate an extension. Larger values increase speed at the expense of sensitivity.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	print "<li><label for =\"partial_matches\" class=\"parameter\">Return up to:</label>\n";
	print $q->popup_menu( -name => 'partial_matches', -id => 'partial_matches', -values => [qw(1 2 3 4 5 6 7 8 9 10)], -default => 1 );
	print " partial match(es)</li>";
	print "<li><label for =\"limit_matches\" class=\"parameter\">Stop after:</label>\n";
	print $q->popup_menu(
		-name    => 'limit_matches',
		-id      => 'limit_matches',
		-values  => [qw(10 20 30 40 50 100 200 500 1000 2000 5000 10000 20000)],
		-default => 200
	);
	print " new matches ";
	print
" <a class=\"tooltip\" title=\"Stop after matching - Limit the number of previously undesignated matches. You may wish to terminate the search after finding a set number of new matches.  You will be able to tag any sequences found and next time these won't be searched (by default) so this enables you to tag in batches.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	print "<li><label for =\"limit_time\" class=\"parameter\">Stop after:</label>\n";
	print $q->popup_menu( -name => 'limit_time', -id => 'limit_time', -values => [qw(1 2 5 10 15 30 60 120 180 240 300)], -default => 5 );
	print " minute(s) ";
	print
" <a class=\"tooltip\" title=\"Stop after time - Searches against lots of loci or for multiple isolates may take a long time. You may wish to terminate the search after a set time.  You will be able to tag any sequences found and next time these won't be searched (by default) so this enables you to tag in batches.\">&nbsp;<i>i</i>&nbsp;</a></li>";

	if ( $self->{'system'}->{'tblastx_tagging'} eq 'yes' ) {
		print "<li><span class=\"warning\">";
		print $q->checkbox( -name => 'tblastx', -label => 'Use TBLASTX' );
		print " <a class=\"tooltip\" title=\"TBLASTX - Compares the six-frame translation of your nucleotide query against 
	the six-frame translation of the sequences in the sequence bin.  This can be VERY SLOW (a few minutes for 
	each comparison. Use with caution.<br /><br />Partial matches may be indicated even when an exact match 
	is found if the matching allele contains a partial codon at one of the ends.  Identical matches will be indicated 
	if the translated sequences match even if the nucleotide sequences don't. For this reason, allele designation 
	tagging is disabled for TBLASTX matching.\">&nbsp;<i>i</i>&nbsp;</a>";
		print "</span></li>\n";
	}
	print "<li>";
	print $q->checkbox( -name => 'hunt', -label => 'Hunt for nearby start and stop codons' );
	print " <a class=\"tooltip\" title=\"Hunt for start/stop codons - If the aligned sequence is not an exact match to an
	existing allele and is not a complete coding sequence with start and stop codons at the ends, selecting this 
	option will hunt for these by walking in and out from the ends in complete codons for up to 6 amino acids.\">&nbsp;<i>i</i>&nbsp;</a>";
	print "</li><li>\n";
	print $q->checkbox( -name => 'rescan_alleles', -label => 'Rescan even if allele designations are already set' );
	print "</li><li>\n";
	print $q->checkbox( -name => 'rescan_seqs', -label => 'Rescan even if allele sequences are tagged' );
	print "</li></ul>\n";
	print "</fieldset>";

	#Only show repetitive loci fields if PCR or probe locus links have been set
	my $pcr_links   = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM pcr_locus")->[0];
	my $probe_links = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM probe_locus")->[0];
	if ( $pcr_links + $probe_links ) {
		print "<fieldset>\n<legend>Repetitive loci</legend>\n";
		print "<ul>";
		if ($pcr_links) {
			print "<li>";
			print $q->checkbox( -name => 'pcr_filter', -label => 'Filter by PCR', -checked => 'checked' );
			print " <a class=\"tooltip\" title=\"Filter by PCR - Loci can be defined by a simulated PCR reaction(s) so that only
			regions of the genome predicted to be amplified will be recognised in the scan. De-selecting this option will ignore this filter and the
			whole sequence bin will be scanned instead.  Partial matches will also be returned (up to the number set in the parameters) even if exact
			matches are found.  De-selecting this option will be necessary if the gene in question is incomplete due to being located at the end
			of a contig since it can not then be bounded by PCR primers.\">&nbsp;<i>i</i>&nbsp;</a>";
			print "</li>\n<li><label for=\"alter_pcr_mismatches\" class=\"parameter\">&Delta; PCR mismatch:</label>\n";
			print $q->popup_menu(
				-name    => 'alter_pcr_mismatches',
				-id      => 'alter_pcr_mismatches',
				-values  => [qw (-3 -2 -1 0 +1 +2 +3)],
				-default => 0
			);
			print
			  " <a class=\"tooltip\" title=\"Change primer mismatch - Each defined PCR reaction will have a parameter specifying the allowed
			number of mismatches per primer. You can increase or decrease this value here, altering the stringency of the reaction.\">&nbsp;<i>i</i>&nbsp;</a>";
			print "</li>";
		}
		if ($probe_links) {
			print "<li>";
			print $q->checkbox( -name => 'probe_filter', -label => 'Filter by probe', -checked => 'checked' );
			print " <a class=\"tooltip\" title=\"Filter by probe - Loci can be defined by a simulated hybridization reaction(s) so that only
			regions of the genome predicted to be within a set distance of a hybridization sequence will be recognised in the scan. De-selecting this 
			option will ignore this filter and the whole sequence bin will be scanned instead.  Partial matches will also be returned (up to the 
			number set in the parameters) even if exact matches are found.\">&nbsp;<i>i</i>&nbsp;</a></li>\n";
			print "<li><label for=\"alter_pcr_mismatches\" class=\"parameter\">&Delta; Probe mismatch:</label>\n";
			print $q->popup_menu(
				-name    => 'alter_probe_mismatches',
				-id      => 'alter_probe_mismatches',
				-values  => [qw (-3 -2 -1 0 +1 +2 +3)],
				-default => 0
			);
			print
" <a class=\"tooltip\" title=\"Change probe mismatch - Each hybridization reaction will have a parameter specifying the allowed
			number of mismatches. You can increase or decrease this value here, altering the stringency of the reaction.\">&nbsp;<i>i</i>&nbsp;</a>";
			print "</li>";
		}
		print "</ul>\n";
		print "</fieldset>";
	}
	print "<fieldset>\n<legend>Restrict included sequences by</legend>\n";
	print "<ul><li><label for=\"seq_method\" class=\"parameter\">Sequence method:</label>";
	print $q->popup_menu( -name => 'seq_method', -id => 'seq_method', -values => [ '', SEQ_METHODS ] );
	print
" <a class=\"tooltip\" title=\"Sequence method - Only include sequences generated from the selected method.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	my $sql = $self->{'db'}->prepare("SELECT id,short_description FROM projects ORDER BY short_description");
	my @projects;
	my %project_labels;
	eval { $sql->execute; };

	if ($@) {
		$logger->error("Can't execute $@");
	}
	while ( my ( $id, $desc ) = $sql->fetchrow_array ) {
		push @projects, $id;
		$project_labels{$id} = $desc;
	}
	if (@projects) {
		unshift @projects, '';
		print "<li><label for=\"project\" class=\"parameter\">Project:</label>";
		print $q->popup_menu( -name => 'project', -id => 'project', -values => \@projects, -labels => \%project_labels );
		print
" <a class=\"tooltip\" title=\"Projects - Only include sequences whose isolate belong to the specified experiment.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	}
	$sql = $self->{'db'}->prepare("SELECT id,description FROM experiments ORDER BY description");
	my @experiments;
	my %exp_labels;
	eval { $sql->execute; };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	while ( my ( $id, $desc ) = $sql->fetchrow_array ) {
		push @experiments, $id;
		$exp_labels{$id} = $desc;
	}
	if (@experiments) {
		unshift @experiments, '';
		print "<li><label for=\"experiment\" class=\"parameter\">Experiment:</label>";
		print $q->popup_menu( -name => 'experiment', -id => 'experiment', -values => \@experiments, -labels => \%exp_labels );
		print
" <a class=\"tooltip\" title=\"Experiments - Only include sequences that have been linked to the specified experiment.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	}
	print "</ul></fieldset>\n";
	print "</div>";
	print "<table style=\"width:95%\"><tr><td style=\"text-align:left\">";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan\" class=\"resetbutton\">Reset</a></td><td style=\"text-align:right\" colspan=\"3\">";
	print $q->submit( -name => 'scan', -label => 'Scan', -class => 'submit' );
	print "</td></tr></table>\n";
	foreach (qw (page db)) {
		print $q->hidden($_);
	}
	print $q->end_form;
	print "</div>\n";
}

sub _scan {
	my ( $self, $labels ) = @_;
	my $q          = $self->{'cgi'};
	my $start_time = time;
	my $time_limit = ( int( $q->param('limit_time') ) || 5 ) * 60;
	my @loci       = $q->param('locus');
	my @ids        = $q->param('isolate_id');
	my @scheme_ids = $q->param('scheme_id');
	if ( !@ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You must select one or more isolates.</p></div>\n";
		return;
	}
	if ( !@loci && !@scheme_ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You must select one or more loci or schemes.</p></div>\n";
		return;
	}
	$self->_add_scheme_loci( \@loci );
	my $header_buffer =
"<div class=\"scrollable\">\n<table class=\"resultstable\"><tr><th>Isolate</th><th>Match</th><th>Locus</th><th>Allele</th><th>% identity</th><th>Alignment length</th><th>Allele length</th><th>E-value</th><th>Sequence bin id</th>
<th>Start</th><th>End</th><th>Predicted start</th><th>Predicted end</th><th>Orientation</th><th>Designate allele</th><th>Tag sequence</th><th>Flag";
	$header_buffer .= " <a class=\"tooltip\" title=\"Flag - Set a status flag for the sequence.  You need to also tag the sequence for
		any flag to take effect.\">&nbsp;<i>i</i>&nbsp;</a>";
	$header_buffer .= "</th></tr>\n";
	print "<div class=\"box\" id=\"resultstable\">\n";
	print $q->start_form;
	my $tag_button = 1;
	my ( @js, @js2, @js3, @js4 );
	my $show_key;
	my $buffer;
	my $first = 1;
	my $limit;
	my $new_alleles;

	if ( BIGSdb::Utils::is_int( $q->param('limit_matches') ) ) {
		$limit = $q->param('limit_matches');
	} else {
		$limit = 10;
	}
	my $match = 0;
	my ( %allele_designation_set, %allele_sequence_tagged );
	my $td = 1;
	my $out_of_time;
	my $match_limit_reached;
	my $file_prefix  = BIGSdb::Utils::get_random();
	my $locus_prefix = BIGSdb::Utils::get_random();
	my $seq_filename = $self->{'config'}->{'tmp_dir'} . "/$file_prefix\_unique_sequences.txt";
	open( my $seqs_fh, '>', $seq_filename ) or $logger->error("Can't open $seq_filename for writing");
	print $seqs_fh "locus\tallele_id\tstatus\tsequence\n";
	my $new_seqs_found;
	my $last_id_checked;
	my @isolates_in_project;
	my $project_id = $q->param('project');
	if ($project_id && BIGSdb::Utils::is_int($project_id)){
		my $list_ref = $self->{'datastore'}->run_list_query("SELECT isolate_id FROM project_members WHERE project_id=?",$project_id);
		if (ref $list_ref eq 'ARRAY'){
			@isolates_in_project = @$list_ref;
		}
	}
	foreach my $isolate_id (@ids) {
		next if $project_id && none {$isolate_id == $_} @isolates_in_project;
		if ( $match >= $limit ) {
			$match_limit_reached = 1;
			last;
		}
		if ( time >= $start_time + $time_limit ) {
			$out_of_time = 1;
			last;
		}
		next if $isolate_id eq '' || $isolate_id eq 'all';
		next if !$self->is_allowed_to_view_isolate($isolate_id);
		$| = 1;
		my %locus_checked;
		foreach my $locus (@loci) {
			if ( $locus =~ /^l_(.+)/ || $locus =~ /^cn_(.+)/ || $locus =~ /^la_(.+)\|\|/ ) {
				$locus = $1;
			}
			next if $locus_checked{$locus};    #prevent multiple checking when locus selected individually and as part of scheme.
			$locus_checked{$locus} = 1;
			if ( $match >= $limit ) {
				$match_limit_reached = 1;
				last;
			}
			if ( time >= $start_time + $time_limit ) {
				$out_of_time = 1;
				last;
			}
			my $allele_seq = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
			next
			  if ( ( !$q->param('rescan_alleles') && defined $self->{'datastore'}->get_allele_id( $isolate_id, $locus ) )
				|| ( !$q->param('rescan_seqs') && ref $allele_seq eq 'ARRAY' && scalar @$allele_seq > 0 ) );
			my ( $exact_matches, $partial_matches ) = $self->_blast( $locus, $isolate_id, $file_prefix, $locus_prefix );
			my $off_end;
			my $i = 1;
			my $new_designation;
			if ( ref $exact_matches && @$exact_matches ) {
				print $header_buffer if $first;
				my %new_matches;
				foreach (@$exact_matches) {
					my $match_key = "$_->{'seqbin_id'}\|$_->{'predicted_start'}|$_->{'predicted_end'}";
					( $off_end, $new_designation ) =
					  $self->_print_row( $isolate_id, $labels, $locus, $i, $_, $td, 1, \@js, \@js2, \@js3, \@js4,
						$new_matches{$match_key} );
					$new_matches{$match_key} = 1;
					$show_key = 1 if $off_end;
					$td = $td == 1 ? 2 : 1;
					$i++;
				}
				$first = 0;
			}
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			if (   ref $partial_matches
				&& @$partial_matches
				&& ( !@$exact_matches || ( $locus_info->{'pcr_filter'} && !$q->param('pcr_filter') ) ) )
			{
				print $header_buffer if $first;
				my %new_matches;
				foreach (@$partial_matches) {
					my $match_key = "$_->{'seqbin_id'}\|$_->{'predicted_start'}|$_->{'predicted_end'}";
					( $off_end, $new_designation ) =
					  $self->_print_row( $isolate_id, $labels, $locus, $i, $_, $td, 0, \@js, \@js2, \@js3, \@js4,
						$new_matches{$match_key} );
					$new_matches{$match_key} = 1;
					if ($off_end) {
						$show_key = 1;
					} else {
						my $length = $_->{'predicted_end'} - $_->{'predicted_start'} + 1;
						my $extract_seq_sql =
						  $self->{'db'}
						  ->prepare("SELECT substring(sequence from $_->{'predicted_start'} for $length) FROM sequence_bin WHERE id=?");
						eval { $extract_seq_sql->execute( $_->{'seqbin_id'} ) };
						if ($@) {
							$logger->error("Can't execute $@");
						}
						my ($seq) = $extract_seq_sql->fetchrow_array;
						$seq = BIGSdb::Utils::reverse_complement($seq) if $_->{'reverse'};
						$new_seqs_found = 1;
						my $new = 1;
						foreach ( @{ $new_alleles->{$locus} } ) {
							if ( $seq eq $_ ) {
								$new = 0;
							}
						}
						if ($new) {
							push @{ $new_alleles->{$locus} }, $seq;
							print $seqs_fh "$locus\t\ttrace not checked\t$seq\n";
						}
					}
					$td = $td == 1 ? 2 : 1;
					$i++;
				}
				$first = 0;
			} else {
				print " ";    #try to prevent time-out.
			}
			if ( $ENV{'MOD_PERL'} ) {
				$self->{'mod_perl_request'}->rflush;
				if ( $self->{'mod_perl_request'}->connection->aborted ) {

					#clean up
					system
					  "rm -f $self->{'config'}->{'secure_tmp_dir'}/*$file_prefix* $self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*";
					return;
				}
			}
			$match++ if $new_designation;
		}

		#delete isolate working files
		system "rm -f $self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*";
		$last_id_checked = $isolate_id;
	}
	close $seqs_fh;

	#delete locus working files
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*";
	if ($first) {
		$tag_button = 0;
	} else {
		$buffer .= "</table></div>\n";
		$buffer .= "<p>* Allele continues beyond end of contig</p>\n" if $show_key;
	}
	if ($tag_button) {
		$" = ';';
		print "<tr class=\"td\"><td colspan=\"14\" /><td>\n";
		print "<input type=\"button\" value=\"All\" onclick='@js' class=\"smallbutton\" />"   if @js;
		print "<input type=\"button\" value=\"None\" onclick='@js2' class=\"smallbutton\" />" if @js2;
		print "</td><td>\n";
		print "<input type=\"button\" value=\"All\" onclick='@js3' class=\"smallbutton\" />"  if @js3;
		print "<input type=\"button\" value=\"None\" onclick='@js4' class=\"smallbutton\" />" if @js4;
		print "</td></tr>\n";
	}
	print $buffer;
	print "<p>Time limit reached (checked up to id-$last_id_checked).</p>"  if $out_of_time;
	print "<p>Match limit reached (checked up to id-$last_id_checked).</p>" if $match_limit_reached;
	if ($new_seqs_found) {
		print "<p><a href=\"/tmp/$file_prefix\_unique_sequences.txt\" target=\"_blank\">New unique sequences</a>\n";
		print
" <a class=\"tooltip\" title=\"Unique sequence - This is a list of new sequences (tab-delimited with locus name) of unique new sequences found in this search.  This can be used to facilitate rapid upload of new sequences to a sequence definition database for allele assignment.\">&nbsp;<i>i</i>&nbsp;</a>";
		print "</p>\n";
	}
	if ($tag_button) {
		$" = ';';
		print $q->submit( -name => 'tag', -label => 'Tag alleles/sequences', -class => 'submit' );
		print "<noscript><p><span class=\"comment\"> Enable javascript for select buttons to work!</span></p></noscript>\n";
		foreach (
			qw (db page isolate_id rescan_alleles rescan_seqs locus scheme_id identity alignment limit_matches limit_time seq_method
			experiment project tblastx hunt pcr_filter alter_pcr_mismatches probe_filter alter_probe_mismatches)
		  )
		{
			print $q->hidden($_);
		}
	} else {
		print "<p>No sequence or allele tags to update.</p>";
	}
	print $q->end_form;
	print "</div>\n";
}

sub _tag {
	my ( @updates, @allele_updates, @pending_allele_updates, @sequence_updates, $history );
	my ( $self, $labels ) = @_;
	my $q = $self->{'cgi'};
	my $pending_sql =
	  $self->{'db'}
	  ->prepare("SELECT COUNT(*) FROM pending_allele_designations WHERE isolate_id=? AND locus=? AND allele_id=? AND sender=?");
	my $sequence_exists_sql = $self->{'db'}->prepare("SELECT COUNT(*) FROM allele_sequences WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=?");
	my @params              = $q->param;
	my @ids                 = $q->param('isolate_id');
	my @loci                = $q->param('locus');
	my @scheme_ids          = $q->param('scheme_id');
	$self->_add_scheme_loci( \@loci );
	@loci = uniq @loci;
	my $sql        = $self->{'db'}->prepare("SELECT sender FROM sequence_bin WHERE id=?");
	my $curator_id = $self->get_curator_id;

	foreach my $isolate_id (@ids) {
		next if !$self->is_allowed_to_view_isolate($isolate_id);
		foreach (@loci) {
			$_ =~ s/^cn_//;
			$_ =~ s/^l_//;
			$_ =~ s/^la_//;
			$_ =~ s/\|\|.+//;
			my @ids;
			my %used;
			my $cleaned_locus = $_;
			$cleaned_locus =~ s/'/\\'/g;
			my $allele_id_to_set;
			my %pending_allele_ids_to_set;

			foreach my $id (@params) {
				next if $id !~ /$_/;
				next if $id !~ /\_$isolate_id\_/;
				my $allele_test = "id_$isolate_id\_$_\_allele";
				my $seq_test    = "id_$isolate_id\_$_\_sequence";
				if ( $id =~ /\Q$allele_test\E\_(\d+)/ || $id =~ /\Q$seq_test\E\_(\d+)/ ) {
					push @ids, $1 if !$used{$1};
					$used{$1} = 1;
				}
			}
			my $display_locus = $self->clean_locus($_);
			foreach my $id (@ids) {
				my $seqbin_id = $q->param("id_$isolate_id\_$_\_seqbin_id_$id");
				if ( $q->param("id_$isolate_id\_$_\_allele_$id") && $q->param("id_$isolate_id\_$_\_allele_id_$id") ) {
					my $allele_id = $q->param("id_$isolate_id\_$_\_allele_id_$id");
					my $set_allele_id = $self->{'datastore'}->get_allele_id( $isolate_id, $_ );
					eval { $sql->execute($seqbin_id); };
					if ($@) {
						$logger->error("Can't execute seqbin lookup $@");
					}
					my $seqbin_info = $sql->fetchrow_hashref;
					my $sender      = $seqbin_info->{'sender'};
					if ( $allele_id_to_set eq '' || !$pending_allele_ids_to_set{$allele_id} ) {
						if ( !defined $set_allele_id && $allele_id_to_set eq '' ) {
							push @updates,
"INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp,comments) VALUES ($isolate_id,'$cleaned_locus','$allele_id',$sender,'confirmed','automatic',$curator_id,'today','today','Scanned from sequence bin')";
							$allele_id_to_set = $allele_id;
							push @allele_updates, ( $labels->{$isolate_id} || $isolate_id ) . ": $display_locus:  $allele_id";
							push @{ $history->{$isolate_id} }, "$_: new designation '$allele_id' (sequence bin scan)";
						} elsif ( $set_allele_id ne $allele_id
							&& $allele_id_to_set ne $allele_id
							&& !$pending_allele_ids_to_set{$allele_id} )
						{
							eval { $pending_sql->execute( $isolate_id, $_, $allele_id, $sender ); };
							if ($@) {
								$logger->error("Can't execute pending allele check $@");
							}
							my ($exists) = $pending_sql->fetchrow_array;
							if ( !$exists ) {
								push @updates,
"INSERT INTO pending_allele_designations (isolate_id,locus,allele_id,sender,method,curator,date_entered,datestamp,comments) VALUES ($isolate_id,'$cleaned_locus','$allele_id',$sender,'automatic',$curator_id,'today','today','Scanned from sequence bin')";
								$pending_allele_ids_to_set{$allele_id} = 1;
								push @pending_allele_updates,
								    ( $labels->{$isolate_id} || $isolate_id )
								  . ": $display_locus:  $allele_id (conflicts with existing designation '"
								  . ( $set_allele_id eq '' ? $allele_id_to_set : $set_allele_id ) . "').";
								push @{ $history->{$isolate_id} }, "$_: new pending designation '$allele_id' (sequence bin scan)";
							}
						}
					}
				}
				if ( $q->param("id_$isolate_id\_$_\_sequence_$id") ) {
					my $start    = $q->param("id_$isolate_id\_$_\_start_$id");
					my $end      = $q->param("id_$isolate_id\_$_\_end_$id");					
					eval { $sequence_exists_sql->execute( $seqbin_id, $_, $start, $end  ) };
					if ($@) {
						$logger->error("Can't execute allele sequence check $@");
					}
					my ($exists) = $sequence_exists_sql->fetchrow_array;
					if ( !$exists ) {
						my $reverse  = $q->param("id_$isolate_id\_$_\_reverse_$id") ? 'TRUE' : 'FALSE';
						my $complete = $q->param("id_$isolate_id\_$_\_complete_$id") ? 'TRUE' : 'FALSE';
						push @updates,
"INSERT INTO allele_sequences (seqbin_id,locus,start_pos,end_pos,reverse,complete,curator,datestamp) VALUES ($seqbin_id,'$cleaned_locus',$start,$end,'$reverse','$complete',$curator_id,'today')";
						push @sequence_updates,
						  ( $labels->{$isolate_id} || $isolate_id ) . ": $display_locus:  Seqbin id: $seqbin_id; $start-$end";
						push @{ $history->{$isolate_id} }, "$_: sequence tagged. Seqbin id: $seqbin_id; $start-$end (sequence bin scan)";
						if ( $q->param("id_$isolate_id\_$_\_sequence_$id\_flag") ) {
							my $flag = $q->param("id_$isolate_id\_$_\_sequence_$id\_flag");
							push @updates,
"INSERT INTO sequence_flags (seqbin_id,locus,start_pos,end_pos,flag,datestamp,curator) VALUES ($seqbin_id,'$cleaned_locus',$start,$end,'$flag','today',$curator_id)";
						}
					}
				}
			}
		}
	}
	if (@updates) {
		eval {
			foreach (@updates)
			{
				$self->{'db'}->do($_);
			}
		};
		if ($@) {
			$" = ', ';
			print
			  "<div class=\"box\" id=\"statusbad\"><p>Database update failed - transaction cancelled - no records have been touched.</p>\n";
			if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
				print
"<p>Data entry would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
				$logger->debug($@);
			} else {
				print "<p>Error message: $@</p>\n";
				$logger->error($@);
			}
			print "</div>\n";
			$self->{'db'}->rollback;
			return;
		} else {
			$self->{'db'}->commit;
			print "<div class=\"box\" id=\"resultsheader\"><p>Database updated ok.</p>";
			print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
			print "<div class=\"box\" id=\"resultstable\">\n";
			$" = "<br />\n";
			if (@allele_updates) {
				print "<h2>Allele designations set</h2>\n";
				print "<p>@allele_updates</p>\n";
			}
			if (@pending_allele_updates) {
				print "<h2>Pending allele designations set</h2>\n";
				print "<p>@pending_allele_updates</p>\n";
			}
			if (@sequence_updates) {
				print "<h2>Allele sequences set</h2>\n";
				print "<p>@sequence_updates</p>\n";
			}
			if ( ref $history eq 'HASH' ) {
				foreach ( keys %$history ) {
					my @message = @{ $history->{$_} };
					$" = '<br />';
					$self->update_history( $_, "@message" );
				}
			}
			print "</div>\n";
		}
	} else {
		print "<div class=\"box\" id=\"resultsheader\"><p>No updates required.</p>\n";
		print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
	}
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $view   = $self->{'system'}->{'view'};
	my $qry =
"SELECT DISTINCT $view.id,$view.$self->{'system'}->{'labelfield'} FROM sequence_bin LEFT JOIN $view ON $view.id=sequence_bin.isolate_id WHERE $view.id IS NOT NULL ORDER BY $view.id";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute; };
	if ($@) {
		$logger->error("Can't execute $qry; $@");
	}
	my @ids;
	my %labels;
	while ( my ( $id, $isolate ) = $sql->fetchrow_array ) {
		push @ids, $id;
		$labels{$id} = "$id) $isolate";
	}
	$self->_print_interface( \@ids, \%labels );
	if ( $q->param('tag') ) {
		$self->_tag( \%labels );
	} elsif ( $q->param('scan') ) {
		$self->_scan( \%labels );
	}
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Sequence tag scan - $desc";
}

sub _add_scheme_loci {
	my ( $self, $loci ) = @_;
	my @scheme_ids = $self->{'cgi'}->param('scheme_id');
	my %locus_selected;
	foreach (@$loci) {
		$locus_selected{$_} = 1;
	}
	foreach (@scheme_ids) {
		my $scheme_loci = $_ ? $self->{'datastore'}->get_scheme_loci($_) : $self->{'datastore'}->get_loci_in_no_scheme;
		foreach my $locus (@$scheme_loci) {
			if ( !$locus_selected{$locus} ) {
				push @$loci, "l_$locus";
				$locus_selected{$locus} = 1;
			}
		}
	}
}

sub _print_row {
	my ( $self, $isolate_id, $labels, $locus, $id, $match, $td, $exact, $js, $js2, $js3, $js4, $warning ) = @_;
	my $q = $self->{'cgi'};
	my $class = " class=\"partialmatch\"" if !$exact;
	my $tooltip;
	my $new_designation = 0;
	my $existing_allele = $self->{'datastore'}->get_allele_id( $isolate_id, $locus );
	if ( $match->{'allele'} eq $existing_allele ) {
		$tooltip = $self->_get_designation_tooltip( $isolate_id, $locus, 'existing' );
	} elsif ( $match->{'allele'} && defined $existing_allele && $existing_allele ne $match->{'allele'} ) {
		$tooltip = $self->_get_designation_tooltip( $isolate_id, $locus, 'clashing' );
	}
	my $seqbin_length =
	  $self->{'datastore'}->run_simple_query( "SELECT length(sequence) FROM sequence_bin WHERE id=?", $match->{'seqbin_id'} )->[0];
	my $off_end;
	my $hunt_for_start_end = 1 if !$exact && $q->param('hunt');
	my $original_start     = $match->{'predicted_start'};
	my $original_end       = $match->{'predicted_end'};
	my ( $predicted_start, $predicted_end, $complete_tooltip );
	my ( $complete_gene, $status );

	#Hunt for nearby start and stop codons.  Walk in from each end by 3 bases, then out by 3 bases, then in by 6 etc.
	my @runs = qw (-3 3 -6 6 -9 9 -12 12 -15 15 -18 18) if $hunt_for_start_end;
  RUN: foreach ( 0, @runs ) {
		my @end_to_adjust = $hunt_for_start_end ? ( 1, 2 ) : (0);
		foreach my $end (@end_to_adjust) {
			if ( $end == 1 ) {
				if (   ( !$status->{'start'} && $match->{'reverse'} )
					|| ( !$status->{'stop'} && !$match->{'reverse'} ) )
				{
					$match->{'predicted_end'} = $original_end + $_;
				}
			} elsif ( $end == 2 ) {
				if (   ( !$status->{'stop'} && $match->{'reverse'} )
					|| ( !$status->{'start'} && !$match->{'reverse'} ) )
				{
					$match->{'predicted_start'} = $original_start + $_;
				}
			}
			if ( $match->{'predicted_start'} < 1 ) {
				$match->{'predicted_start'} = '1*';
				$off_end = 1;
			}
			if ( $match->{'predicted_end'} > $seqbin_length ) {
				$match->{'predicted_end'} = "$seqbin_length\*";
				$off_end = 1;
			}
			$predicted_start = $match->{'predicted_start'};
			$predicted_start =~ s/\*//;
			$predicted_end = $match->{'predicted_end'};
			$predicted_end =~ s/\*//;
			my $predicted_length = $predicted_end - $predicted_start + 1;
			$predicted_length = 1 if $predicted_length < 1;
			my $seq_ref =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT substring(sequence from $predicted_start for $predicted_length) FROM sequence_bin WHERE id=?",
				$match->{'seqbin_id'} );

			if ( ref $seq_ref eq 'ARRAY' ) {
				$seq_ref->[0] = BIGSdb::Utils::reverse_complement( $seq_ref->[0] ) if $match->{'reverse'};
				( $complete_gene, $status ) = $self->_is_complete_gene( $seq_ref->[0] );
				if ($complete_gene) {
					$complete_tooltip =
"<a class=\"cds\" title=\"CDS - this is a complete coding sequence including start and terminating stop codons with no internal stop codons.\">CDS</a>";
					last RUN;
				}
			}
		}
	}
	if ( $hunt_for_start_end && !$complete_gene ) {
		$match->{'predicted_end'}   = $original_end;
		$predicted_end              = $original_end;
		$match->{'predicted_start'} = $original_start;
		$predicted_start            = $original_start;
		if ( $match->{'predicted_start'} < 1 ) {
			$match->{'predicted_start'} = '1*';
			$off_end = 1;
		}
		if ( $match->{'predicted_end'} > $seqbin_length ) {
			$match->{'predicted_end'} = "$seqbin_length\*";
			$off_end = 1;
		}
	}
	my $cleaned_locus = $self->clean_locus($locus);
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $translate  = $locus_info->{'coding_sequence'} ? 1 : 0;
	my $orf        = $locus_info->{'orf'} || 1;
	if ($warning) {
		print "<tr style=\"color:white;background:red\">";
	} else {
		print "<tr class=\"td$td\">";
	}
	print "<td>"
	  . ( $labels->{$isolate_id} || $isolate_id )
	  . "</td><td$class>"
	  . ( $exact ? 'exact' : 'partial' )
	  . "</td><td$class>$cleaned_locus";
	  print " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
	  print "</td><td$class>$match->{'allele'}$tooltip</td>
<td>$match->{'identity'}</td><td>$match->{'alignment'}</td>
<td>$match->{'length'}</td><td>$match->{'e-value'}</td><td>$match->{'seqbin_id'} </td>
<td>$match->{'start'}</td><td>$match->{'end'} </td>
<td>$match->{'predicted_start'}</td><td>$match->{'predicted_end'} <a target=\"_blank\" class=\"extract_tooltip\" href=\"$self->{'script_name'}?db=$self->{'instance'}&amp;page=extractedSequence&amp;seqbin_id=$match->{'seqbin_id'}&amp;start=$predicted_start&amp;end=$predicted_end&amp;reverse=$match->{'reverse'}&amp;translate=$translate&amp;orf=$orf\">extract&nbsp;&rarr;</a>$complete_tooltip</td><td style=\"font-size:2em\">"
	  . ( $match->{'reverse'} ? '&larr;' : '&rarr;' ) . "</td><td>";
	my $sender = $self->{'datastore'}->run_simple_query( "SELECT sender FROM sequence_bin WHERE id=?", $match->{'seqbin_id'} )->[0];
	my $matching_pending =
	  $self->{'datastore'}->run_simple_query(
		"SELECT COUNT(*) FROM pending_allele_designations WHERE isolate_id=? AND locus=? AND allele_id=? AND sender=? AND method=?",
		$isolate_id, $locus, $match->{'allele'}, $sender, 'automatic' )->[0];
	my $seq_disabled = 0;
	$cleaned_locus = $locus;
	$cleaned_locus =~ s/\\/\\\\/g;
	$cleaned_locus =~ s/'/__prime__/g;
	$cleaned_locus =~ s/,/__comma__/g;
	$cleaned_locus =~ s/ /__space__/g;
	$cleaned_locus =~ s/\(/_OPEN_/g;
	$cleaned_locus =~ s/\)/_CLOSE_/g;
	$exact = 0 if $warning;

	if ( $exact && $match->{'allele'} ne $existing_allele && !$matching_pending && $match->{'allele'} ne 'ref' && !$q->param('tblastx') ) {
		print $q->checkbox(
			-name    => "id_$isolate_id\_$locus\_allele_$id",
			-id      => "id_$isolate_id\_$cleaned_locus\_allele_$id",
			-label   => '',
			-checked => $exact
		);
		print $q->hidden( "id_$isolate_id\_$locus\_seqbin_id_$id", $match->{'seqbin_id'} );
		push @$js,  "\$(\"#id_$isolate_id\_$cleaned_locus\_allele_$id\").attr(\"checked\",true)";
		push @$js2, "\$(\"#id_$isolate_id\_$cleaned_locus\_allele_$id\").attr(\"checked\",false)";
		$new_designation = 1;
	} else {
		print $q->checkbox( -name => "id_$isolate_id\_$locus\_allele_$id", -label => '', disabled => 'disabled' );
	}
	print "</td><td>";
	my $allele_sequence_exists =
	  $self->{'datastore'}
	  ->run_simple_query( "SELECT COUNT(*) FROM allele_sequences WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=?", $match->{'seqbin_id'}, $locus, $predicted_start, $predicted_end )->[0];
	if ( !$allele_sequence_exists ) {
		print $q->checkbox(
			-name    => "id_$isolate_id\_$locus\_sequence_$id",
			-id      => "id_$isolate_id\_$cleaned_locus\_sequence_$id",
			-label   => '',
			-checked => $exact
		);
		push @$js3, "\$(\"#id_$isolate_id\_$cleaned_locus\_sequence_$id\").attr(\"checked\",true)";
		push @$js4, "\$(\"#id_$isolate_id\_$cleaned_locus\_sequence_$id\").attr(\"checked\",false)";
		$new_designation = 1;
		print "</td><td>";
		print $q->popup_menu(
			-name   => "id_$isolate_id\_$locus\_sequence_$id\_flag",
			-id     => "id_$isolate_id\_$cleaned_locus\_sequence_$id\_flag",
			-values => [ '', SEQ_FLAGS ]
		);
	} else {
		print $q->checkbox( -name => "id_$isolate_id\_$locus\_sequence_$id", -label => '', disabled => 'disabled' );
		$seq_disabled = 1;
		print "</td><td>";
		my $flags =
		  $self->{'datastore'}
		  ->run_list_query( "SELECT flag FROM sequence_flags WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=? ORDER BY flag",
			$match->{'seqbin_id'}, $locus, $predicted_start, $predicted_end );
		foreach (@$flags) {
			print " <a class=\"seqflag_tooltip\">$_</a>";
		}
	}
	if ($exact) {
		print $q->hidden( "id_$isolate_id\_$locus\_allele_id_$id", $match->{'allele'} );
	}
	if ( !$seq_disabled ) {
		print $q->hidden( "id_$isolate_id\_$locus\_start_$id",     $predicted_start );
		print $q->hidden( "id_$isolate_id\_$locus\_end_$id",       $predicted_end );
		print $q->hidden( "id_$isolate_id\_$locus\_reverse_$id",   $match->{'reverse'} );
		print $q->hidden( "id_$isolate_id\_$locus\_complete_$id",  1 ) if !$off_end;
		print $q->hidden( "id_$isolate_id\_$locus\_seqbin_id_$id", $match->{'seqbin_id'} );
	}
	print "</td></tr>\n";
	return ( $off_end, $new_designation );
}

sub _simulate_PCR {
	my ( $self, $fasta_file, $locus ) = @_;
	my $q = $self->{'cgi'};
	my $reactions =
	  $self->{'datastore'}
	  ->run_list_query_hashref( "SELECT pcr.* FROM pcr LEFT JOIN pcr_locus ON pcr.id = pcr_locus.pcr_id WHERE locus=?", $locus );
	return if !@$reactions;
	my $temp          = BIGSdb::Utils::get_random();
	my $reaction_file = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_reactions.txt";
	my $results_file  = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_results.txt";
	open( my $fh, '>', $reaction_file );
	my $max_primer_mismatch = 0;
	my $conditions;

	foreach (@$reactions) {
		foreach my $primer (qw (primer1 primer2)) {
			$_->{$primer} =~ tr/ //;
		}
		my $min_length = $_->{'min_length'} || 1;
		my $max_length = $_->{'max_length'} || 50000;
		$max_primer_mismatch = $_->{'max_primer_mismatch'} if $_->{'max_primer_mismatch'} > $max_primer_mismatch;
		if ( $q->param('alter_pcr_mismatches') && $q->param('alter_pcr_mismatches') =~ /([\-\+]\d)/ ) {
			my $delta = $1;
			$max_primer_mismatch += $delta;
			$max_primer_mismatch = 0 if $max_primer_mismatch < 0;
		}
		print $fh "$_->{'id'}\t$_->{'primer1'}\t$_->{'primer2'}\t$min_length\t$max_length\n";
		$conditions->{ $_->{'id'} } = $_;
	}
	close $fh;
	system(
"$self->{'config'}->{'ipcress_path'} --input $reaction_file --sequence $fasta_file --mismatch $max_primer_mismatch --pretty false > $results_file 2> /dev/null"
	);
	my @pcr_products;
	open( $fh, '<', $results_file );
	while (<$fh>) {
		if ( $_ =~ /^ipcress:/ ) {
			my ( undef, $seq_id, $reaction_id, $length, undef, $start, $mismatch1, undef, $end, $mismatch2, $desc ) = split /\s+/, $_;
			next if $desc =~ /single/;    #product generated by one primer only.
			my ( $seqbin_id, undef ) = split /:/, $seq_id;
			$logger->debug("Seqbin_id:$seqbin_id; $start-$end; mismatch1:$mismatch1; mismatch2:$mismatch2");
			next
			  if $mismatch1 > $conditions->{$reaction_id}->{'max_primer_mismatch'}
				  || $mismatch2 > $conditions->{$reaction_id}->{'max_primer_mismatch'};
			my $product =
			  { 'seqbin_id' => $seqbin_id, 'start' => $start, 'end' => $end, 'mismatch1' => $mismatch1, 'mismatch2' => $mismatch2 };
			push @pcr_products, $product;
		}
	}
	close $fh;
	unlink $reaction_file, $results_file;
	return \@pcr_products;
}

sub _simulate_hybridization {
	my ( $self, $fasta_file, $locus ) = @_;
	my $q      = $self->{'cgi'};
	my $probes = $self->{'datastore'}->run_list_query_hashref(
"SELECT probes.id,probes.sequence,probe_locus.* FROM probes LEFT JOIN probe_locus ON probes.id = probe_locus.probe_id WHERE locus=?",
		$locus
	);
	return if !@$probes;
	system("$self->{'config'}->{'blast_path'}/formatdb -i $fasta_file -p F -o T");
	my $file_prefix      = BIGSdb::Utils::get_random();
	my $probe_fasta_file = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_probe.txt";
	my $results_file     = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_results.txt";
	open( my $fh, '>', $probe_fasta_file ) or $logger->error("Can't open temp file $probe_fasta_file for writing");
	my %probe_info;

	foreach (@$probes) {
		$_->{'sequence'} =~ s/\s//g;
		print $fh ">$_->{'id'}\n$_->{'sequence'}\n";
		$_->{'max_mismatch'} = 0 if !$_->{'max_mismatch'};
		if ( $q->param('alter_probe_mismatches') && $q->param('alter_probe_mismatches') =~ /([\-\+]\d)/ ) {
			my $delta = $1;
			$_->{'max_mismatch'} += $delta;
			$_->{'max_mismatch'} = 0 if $_->{'max_mismatch'} < 0;
		}
		$_->{'max_gaps'} = 0 if !$_->{'max_gaps'};
		$_->{'min_alignment'} = length $_->{'sequence'} if !$_->{'min_alignment'};
		$probe_info{ $_->{'id'} } = $_;
	}
	close $fh;
	my $seq_count = scalar @$probes;
	system(
"$self->{'config'}->{'blast_path'}/blastall -B $seq_count -b 1000 -p blastn -d $fasta_file -i $probe_fasta_file -o $results_file -m8 -F F 2> /dev/null"
	);
	my @matches;
	if ( -e $results_file ) {
		open( $fh, '<', $results_file );
		while (<$fh>) {
			my @record = split /\t/, $_;
			my $match;
			$match->{'probe_id'}  = $record[0];
			$match->{'seqbin_id'} = $record[1];
			$match->{'alignment'} = $record[3];
			next if $match->{'alignment'} < $probe_info{ $match->{'probe_id'} }->{'min_alignment'};
			$match->{'mismatches'} = $record[4];
			next if $match->{'mismatches'} > $probe_info{ $match->{'probe_id'} }->{'max_mismatch'};
			$match->{'gaps'} = $record[5];
			next if $match->{'gaps'} > $probe_info{ $match->{'probe_id'} }->{'gaps'};

			if ( $record[8] < $record[9] ) {
				$match->{'start'} = $record[8];
				$match->{'end'}   = $record[9];
			} else {
				$match->{'start'} = $record[9];
				$match->{'end'}   = $record[8];
			}
			$logger->debug("Seqbin: $match->{'seqbin_id'}; Start: $match->{'start'}; End: $match->{'end'}");
			push @matches, $match;
		}
		close $fh;
		unlink $results_file;
	}
	unlink $probe_fasta_file;
	return \@matches;
}

sub _blast {
	my ( $self, $locus, $isolate_id, $file_prefix, $locus_prefix ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $q          = $self->{'cgi'};
	my $program;
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		$program = $self->{'cgi'}->param('tblastx') ? 'tblastx' : 'blastn';
	} else {
		$program = 'blastx';
	}
	my $temp_infile  = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_file.txt";
	my $temp_outfile = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_outfile.txt";
	my $clean_locus  = $locus;
	$clean_locus =~ s/\W/_/g;
	$clean_locus = $1 if $clean_locus =~ /(\w*)/;    #avoid taint check
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$locus_prefix\_fastafile_$clean_locus.txt";
	$temp_fastafile =~ s/\\/\\\\/g;
	$temp_fastafile =~ s/'/__prime__/g;
	my $outfile_url      = "$file_prefix\_outfile.txt";
	my $logger_benchmark = get_logger('BIGSdb.Application_Benchmark');
	my $start            = gettimeofday();
	my $elapsed;

	#create fasta index
	#only need to create this once for each locus (per run), so check if file exists first
	#this should then be deleted by the calling function!
	if ( !-e $temp_fastafile ) {
		open( my $fasta_fh, '>', $temp_fastafile ) or $logger->error("Can't open temp file $temp_fastafile for writing");
		if ( $locus_info->{'dbase_name'} ) {
			my $seqs_ref = $self->{'datastore'}->get_locus($locus)->get_all_sequences;
			return if !keys %$seqs_ref;
			foreach ( keys %$seqs_ref ) {
				next if !length $seqs_ref->{$_};
				print $fasta_fh ">$_\n$seqs_ref->{$_}\n";
			}
		} else {
			return if !$locus_info->{'reference_sequence'};
			print $fasta_fh ">ref\n$locus_info->{'reference_sequence'}\n";
		}
		close $fasta_fh;
		( $elapsed = gettimeofday() - $start ) =~ s/(^\d{1,}\.\d{4}).*$/$1/;
		$logger_benchmark->debug("Creating locus FASTA file : $elapsed seconds");
		if ( $locus_info->{'data_type'} eq 'DNA' ) {
			system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p F -o T");
		} else {
			system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p T -o T");
		}
		( $elapsed = gettimeofday() - $start ) =~ s/(^\d{1,}\.\d{4}).*$/$1/;
		$logger_benchmark->debug("Formatting for FASTA : $elapsed seconds");
	}

	#create query fasta file
	#only need to create this once for each isolate (per run), so check if file exists first
	#this should then be deleted by the calling function!
	my $seq_count;
	if ( !-e $temp_infile ) {
		my $qry =
"SELECT DISTINCT sequence_bin.id,sequence FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id=seqbin_id WHERE sequence_bin.isolate_id=?";
		my @criteria = ($isolate_id);
		my $method   = $self->{'cgi'}->param('seq_method');
		if ($method) {
			if ( !any { $_ eq $method } SEQ_METHODS ) {
				$logger->error("Invalid method $method");
				return;
			}
			$qry .= " AND method=?";
			push @criteria, $method;
		}
		my $experiment = $self->{'cgi'}->param('experiment');
		if ($experiment) {
			if ( !BIGSdb::Utils::is_int($experiment) ) {
				$logger->error("Invalid experiment $experiment");
				return;
			}
			$qry .= " AND experiment_id=?";
			push @criteria, $experiment;
		}
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute(@criteria); };
		if ($@) {
			$logger->error("Can't execute $qry $@");
		}
		open( my $infile_fh, '>', $temp_infile ) or $logger->error("Can't open temp file $temp_infile for writing");
		while ( my ( $id, $seq ) = $sql->fetchrow_array ) {
			$seq_count++;
			print $infile_fh ">$id\n$seq\n";
		}
		close $infile_fh;
		open( my $seqcount_fh, '>', "$temp_infile\_seqcount" ) or $logger->error("Can't open temp file $temp_infile\_seqcount for writing");
		print $seqcount_fh "$seq_count";
		close $seqcount_fh;
	} else {
		open( my $seqcount_fh, '<', "$temp_infile\_seqcount" ) or $logger->error("Can't open temp file $temp_infile\_seqcount for reading");
		$seq_count = $1 if <$seqcount_fh> =~ /(\d+)/;
		close $seqcount_fh;
	}
	( $elapsed = gettimeofday() - $start ) =~ s/(^\d{1,}\.\d{4}).*$/$1/;
	$logger_benchmark->debug("Create query FASTA file : $elapsed seconds");
	my ( $pcr_products, $probe_matches );
	if ( $locus_info->{'pcr_filter'} && $q->param('pcr_filter') ) {
		if ( $self->{'config'}->{'ipcress_path'} ) {
			$pcr_products = $self->_simulate_PCR( $temp_infile, $locus );
			return if !@$pcr_products;
		} else {
			$logger->error("Ipcress path is not set in bigsdb.conf.  PCR simulation can not be done so whole genome will be used.");
		}
	}
	if ( $locus_info->{'probe_filter'} && $q->param('probe_filter') ) {
		$probe_matches = $self->_simulate_hybridization( $temp_infile, $locus );
		return if !@$probe_matches;
	}
	my $blastn_word_size = $1 if $self->{'cgi'}->param('word_size') =~ /(\d+)/;
	my $word_size = $program eq 'blastn' ? ( $blastn_word_size || 15 ) : 0;
	system(
"$self->{'config'}->{'blast_path'}/blastall -B $seq_count -b 10 -p $program -W $word_size -d $temp_fastafile -i $temp_infile -o $temp_outfile -m8 -F F 2> /dev/null"
	);
	( $elapsed = gettimeofday() - $start ) =~ s/(^\d{1,}\.\d{4}).*$/$1/;
	$logger_benchmark->debug("Running BLAST : $elapsed seconds");
	my ( $exact_matches, $matched_regions, $partial_matches );
	my $pcr_filter   = !$q->param('pcr_filter')   ? 0 : $locus_info->{'pcr_filter'};
	my $probe_filter = !$q->param('probe_filter') ? 0 : $locus_info->{'probe_filter'};

	if ( -e "$self->{'config'}->{'secure_tmp_dir'}/$outfile_url" ) {
		( $exact_matches, $matched_regions ) =
		  $self->_parse_blast_exact( $locus, $outfile_url, $pcr_filter, $pcr_products, $probe_filter, $probe_matches );
		$partial_matches =
		  $self->_parse_blast_partial( $locus, $matched_regions, $outfile_url, $pcr_filter, $pcr_products, $probe_filter, $probe_matches )
		  if !@$exact_matches
			  || ( $locus_info->{'pcr_filter'} && !$q->param('pcr_filter') && $locus_info->{'probe_filter'} && !$q->param('probe_filter') );
	} else {
		$logger->debug("$self->{'config'}->{'secure_tmp_dir'}/$outfile_url does not exist");
	}
	( $elapsed = gettimeofday() - $start ) =~ s/(^\d{1,}\.\d{4}).*$/$1/;
	$logger_benchmark->debug("Parsing BLAST results : $elapsed seconds");

	#Calling function should delete working files.  This is not done here as they can be re-used
	#if multiple loci are being scanned for the same isolate.
	return ( $exact_matches, $partial_matches );
}

sub _parse_blast_exact {
	my ( $self, $locus, $blast_file, $pcr_filter, $pcr_products, $probe_filter, $probe_matches ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \@; );
	my @matches;
	my $ref_seq_sql = $self->{'db'}->prepare("SELECT length(reference_sequence) FROM loci WHERE id=?");
	my $lengths;
	my $matched_already;
	my $region_matched_already;
  LINE: while ( my $line = <$blast_fh> ) {
		my $match;
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		if ( $record[2] == 100 ) {    #identity
			my $length;
			if ( ref $lengths ne 'HASH' ) {
				if ( $record[1] eq 'ref' ) {
					eval {
						$ref_seq_sql->execute($locus);
						( $lengths->{'ref'} ) = $ref_seq_sql->fetchrow_array;
					};
					if ($@) {
						$logger->error("Can't execute ref_seq query $@");
					}
				} else {
					$lengths = $self->{'datastore'}->get_locus($locus)->get_all_sequence_lengths;
				}
			}
			$length = $lengths->{ $record[1] };
			if (
				(
					(
						$record[8] == 1             #sequence start position
						&& $record[9] == $length    #end position
					)
					|| (
						$record[8] == $length       #sequence start position (reverse complement)
						&& $record[9] == 1          #end position
					)
				)
				&& !$record[4]                      #no gaps
			  )
			{
				$match->{'seqbin_id'} = $record[0];
				$match->{'allele'}    = $record[1];
				$match->{'identity'}  = $record[2];
				$match->{'alignment'} = $self->{'cgi'}->param('tblastx') ? ( $record[3] * 3 ) : $record[3];
				$match->{'length'}    = $length;
				if ( $record[6] < $record[7] ) {
					$match->{'start'} = $record[6];
					$match->{'end'}   = $record[7];
				} else {
					$match->{'start'} = $record[7];
					$match->{'end'}   = $record[6];
				}
				if ($pcr_filter) {
					my $within_amplicon = 0;
					foreach (@$pcr_products) {
						next
						  if $match->{'seqbin_id'} != $_->{'seqbin_id'}
							  || $match->{'start'} < $_->{'start'}
							  || $match->{'end'} > $_->{'end'};
						$within_amplicon = 1;
					}
					next LINE if !$within_amplicon;
				}
				if ($probe_filter) {
					next LINE if !$self->_probe_filter_match( $locus, $match, $probe_matches );
				}
				$match->{'predicted_start'} = $match->{'start'};
				$match->{'predicted_end'}   = $match->{'end'};
				$match->{'reverse'}         = 1
				  if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) );
				$match->{'e-value'} = $record[10];
				next if $matched_already->{ $match->{'allele'} }->{ $match->{'predicted_start'} };
				push @matches, $match;
				$matched_already->{ $match->{'allele'} }->{ $match->{'predicted_start'} }           = 1;
				$region_matched_already->{ $match->{'seqbin_id'} }->{ $match->{'predicted_start'} } = 1;
			}
		}
	}
	close $blast_fh;
	return \@matches, $region_matched_already;
}

sub _parse_blast_partial {
	my @matches;
	my ( $self, $locus, $exact_matched_regions, $blast_file, $pcr_filter, $pcr_products, $probe_filter, $probe_matches ) = @_;
	my $identity  = $self->{'cgi'}->param('identity');
	my $alignment = $self->{'cgi'}->param('alignment');
	$identity  = 70 if !BIGSdb::Utils::is_int($identity);
	$alignment = 50 if !BIGSdb::Utils::is_int($alignment);
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	my $ref_seq_sql = $self->{'db'}->prepare("SELECT length(reference_sequence) FROM loci WHERE id=?");
	my %lengths;
  LINE: while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		if ( !$lengths{ $record[1] } ) {
			if ( $record[1] eq 'ref' ) {
				eval {
					$ref_seq_sql->execute($locus);
					( $lengths{ $record[1] } ) = $ref_seq_sql->fetchrow_array;
				};
				if ($@) {
					$logger->error("Can't execute ref_seq query $@");
				}
			} else {
				my $seq_ref = $self->{'datastore'}->get_locus($locus)->get_allele_sequence( $record[1] );
				$lengths{ $record[1] } = length($$seq_ref);
			}
		}
		my $length = $lengths{ $record[1] };
		if ( $self->{'cgi'}->param('tblastx') ) {
			$record[3] *= 3;
		}
		my $quality = $record[3] * $record[2];    #simple metric of alignment length x percentage identity
		if ( $record[3] > $alignment * 0.01 * $length && $record[2] > $identity ) {
			my $match;
			$match->{'quality'}   = $quality;
			$match->{'seqbin_id'} = $record[0];
			$match->{'allele'}    = $record[1];
			$match->{'identity'}  = $record[2];
			$match->{'length'}    = $length;
			$match->{'alignment'} = $record[3];
			$match->{'reverse'}   = 1
			  if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) );

			if ( $record[6] < $record[7] ) {
				$match->{'start'} = $record[6];
				$match->{'end'}   = $record[7];
			} else {
				$match->{'start'} = $record[7];
				$match->{'end'}   = $record[6];
			}
			if ( $length > $match->{'alignment'} ) {
				if ( $match->{'reverse'} ) {
					if ( $record[8] < $record[9] ) {
						$match->{'predicted_start'} = $match->{'start'} - $length + $record[9];
						$match->{'predicted_end'}   = $match->{'end'} + $record[8] - 1;
					} else {
						$match->{'predicted_start'} = $match->{'start'} - $length + $record[8];
						$match->{'predicted_end'}   = $match->{'end'} + $record[9] - 1;
					}
				} else {
					if ( $record[8] < $record[9] ) {
						$match->{'predicted_start'} = $match->{'start'} - $record[8] + 1;
						$match->{'predicted_end'}   = $match->{'end'} + $length - $record[9];
					} else {
						$match->{'predicted_start'} = $match->{'start'} - $record[9] + 1;
						$match->{'predicted_end'}   = $match->{'end'} + $length - $record[8];
					}
				}
			} else {
				$match->{'predicted_start'} = $match->{'start'};
				$match->{'predicted_end'}   = $match->{'end'};
			}

			#Don't handle exact matches - these are handled elsewhere.
			next if $exact_matched_regions > { $match->{'seqbin_id'} }->{ $match->{'predicted_start'} };
			$match->{'e-value'} = $record[10];
			if ($pcr_filter) {
				my $within_amplicon = 0;
				foreach (@$pcr_products) {
					next
					  if $match->{'seqbin_id'} != $_->{'seqbin_id'}
						  || $match->{'start'} < $_->{'start'}
						  || $match->{'end'} > $_->{'end'};
					$within_amplicon = 1;
				}
				next LINE if !$within_amplicon;
			}
			if ($probe_filter) {
				next LINE if !$self->_probe_filter_match( $locus, $match, $probe_matches );
			}

			#check if match already found with same predicted start or end points
			my $exists;
			foreach (@matches) {
				if (
					$_->{'seqbin_id'} == $match->{'seqbin_id'}
					&& (   $_->{'predicted_start'} == $match->{'predicted_start'}
						|| $_->{'predicted_end'} == $match->{'predicted_end'} )
				  )
				{
					$exists = 1;
				}
			}
			if ( !$exists ) {
				push @matches, $match;
			}
		}
	}
	close $blast_fh;

	#Only return the number of matches selected by 'partial_matches' parameter
	@matches = sort {
		{ $matches[$a] }
		->{'quality'} <=> { $matches[$b] }->{'quality'}
	} @matches;
	my $partial_matches = $self->{'cgi'}->param('partial_matches');
	$partial_matches = 1 if !BIGSdb::Utils::is_int($partial_matches) || $partial_matches < 1;
	while ( @matches > $partial_matches ) {
		pop @matches;
	}
	return \@matches;
}

sub _probe_filter_match {
	my ( $self, $locus, $blast_match, $probe_matches ) = @_;
	my $good_match = 0;
	my %probe_info;
	foreach (@$probe_matches) {
		if ( !$probe_info{ $_->{'probe_id'} } ) {
			$probe_info{ $_->{'probe_id'} } =
			  $self->{'datastore'}
			  ->run_simple_query_hashref( "SELECT * FROM probe_locus WHERE locus=? AND probe_id=?", $locus, $_->{'probe_id'} );
		}
		next if $blast_match->{'seqbin_id'} != $_->{'seqbin_id'};
		my $probe_distance = -1;
		if ( $blast_match->{'start'} > $_->{'end'} ) {
			$probe_distance = $blast_match->{'start'} - $_->{'end'};
		}
		if ( $blast_match->{'end'} < $_->{'start'} ) {
			my $end_distance = $_->{'start'} - $blast_match->{'end'};
			if ( ( $end_distance < $probe_distance ) || ( $probe_distance == -1 ) ) {
				$probe_distance = $end_distance;
			}
		}
		next if ( $probe_distance > $probe_info{ $_->{'probe_id'} }->{'max_distance'} ) || $probe_distance == -1;
		$logger->debug("Probe distance: $probe_distance");
		return 1;
	}
	return 0;
}

sub _get_designation_tooltip {
	my ( $self, $isolate_id, $locus, $status ) = @_;
	my $class;
	my $text;
	if ( $status eq 'existing' ) {
		$class = 'existing_tooltip';
		$text  = 'existing';
	} else {
		$class = 'clashing_tooltip';
		$text  = 'conflict';
	}
	my $buffer = 'Existing designation - ';
	my $allele = $self->{'datastore'}->get_allele_designation( $isolate_id, $locus );
	my $sender = $self->{'datastore'}->get_user_info( $allele->{'sender'} );
	$buffer .= "allele: $allele->{'allele_id'} ";
	$buffer .= "($allele->{'comments'}) "
	  if $_->{'comments'};
	$buffer .= "[$sender->{'first_name'} $sender->{'surname'}; $allele->{'method'}; $allele->{'datestamp'}]";
	if ( $class ne 'existing' ) {
		my $pending = $self->{'datastore'}->get_pending_allele_designations( $isolate_id, $locus );
		if (@$pending) {
			$buffer .= '<p /><h3>pending designations</h3>';
			foreach (@$pending) {
				my $sender = $self->{'datastore'}->get_user_info( $_->{'sender'} );
				$buffer .= "allele: $_->{'allele_id'} ";
				$buffer .= "($_->{'comments'}) "
				  if $_->{'comments'};
				$buffer .= "[$sender->{'first_name'} $sender->{'surname'}; $_->{'method'}; $_->{'datestamp'}]<br />";
			}
		}
	}
	return " <a class=\"$class\" title=\"$buffer\">$text</a>";
}

sub _is_complete_gene {
	my ( $self, $seq ) = @_;
	my $status;

	#Check that sequence has an initial start codon,
	my $start = substr( $seq, 0, 3 );
	$status->{'start'} = 1 if any { $start eq $_ } qw (ATG GTG TTG);

	#and a stop codon
	my $stop = substr( $seq, -3 );
	$status->{'stop'} = 1 if any { $stop eq $_ } qw (TAA TGA TAG);

	#is a multiple of 3
	$status->{'in_frame'} = 1 if length($seq) / 3 == int( length($seq) / 3 );

	#and has no internal stop codons
	$status->{'no_internal_stops'} = 1;
	for ( my $i = 0 ; $i < length($seq) - 3 ; $i += 3 ) {
		my $codon = substr( $seq, $i, 3 );
		$status->{'no_internal_stops'} = 0 if any { $codon eq $_ } qw (TAA TGA TAG);
	}
	if ( $status->{'start'} && $status->{'stop'} && $status->{'in_frame'} && $status->{'no_internal_stops'} ) {
		return ( 1, $status );
	}
	return ( 0, $status );
}
1;
