# $Id$
#
# BioPerl module for Bio::SearchIO::fasta
#
# Cared for by Jason Stajich <jason@bioperl.org>
#
# Copyright Jason Stajich
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::SearchIO::fasta - A SearchIO parser for FASTA results

=head1 SYNOPSIS

# Do not use this object directly, use it through the SearchIO system
    use Bio::SearchIO;
    my $searchio = new Bio::SearchIO(-format => 'fasta',
				     -file   => 'report.FASTA');
    while( my $report = $searchio->next_report ) {
	# ....
    }

=head1 DESCRIPTION

This object contains the event based parsing code for FASTA format reports.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org              - General discussion
  http://bioperl.org/MailList.shtml  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via
email or the web:

  bioperl-bugs@bioperl.org
  http://bioperl.org/bioperl-bugs/

=head1 AUTHOR - Jason Stajich

Email jason@bioperl.org

Describe contact details here

=head1 CONTRIBUTORS

Additional contributors names and emails here

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::SearchIO::fasta;
use vars qw(@ISA %MODEMAP %MAPPING);
use strict;

# Object preamble - inherits from Bio::Root::RootI

use Bio::SearchIO;
use POSIX;

BEGIN { 
    # mapping of NCBI Blast terms to Bioperl hash keys
    %MODEMAP = ('FastaOutput' => 'report',
		'Hit'         => 'subject',
		'Hsp'         => 'hsp'
		);

    # This should really be done more intelligently, like with
    # XSLT

    %MAPPING = ( 
		 'Hsp_bit-score' => 'bits',
		 'Hsp_score'     => 'score',
		 'Hsp_sw-score'  => 'swscore',
		 'Hsp_evalue'    => 'evalue',
		 'Hsp_query-from'=> 'querystart',
		 'Hsp_query-to'  => 'queryend',
		 'Hsp_hit-from'  => 'subjectstart',
		 'Hsp_hit-to'    => 'subjectend',
		 'Hsp_positive'  => 'positive',
		 'Hsp_identity'  => 'match',
		 'Hsp_gaps'      => 'gaps',
		 'Hsp_qseq'      => 'queryseq',
		 'Hsp_hseq'      => 'subjectseq',
		 'Hsp_midline'   => 'homolseq',
		 'Hsp_align-len' => 'hsplen',
		 'Hsp_query-frame'=> 'queryframe',
		 'Hsp_hit-frame'  => 'subjectframe',

		 'Hit_id'        => 'subjectname',
		 'Hit_len'       => 'subjectlen',
		 'Hit_accession' => 'subjectacc',
		 'Hit_def'       => 'subjectdesc',
		 
		 'FastaOutput_program'  => 'programname',
		 'FastaOutput_version'  => 'programver',
		 'FastaOutput_query-def'=> 'queryname',
		 'FastaOutput_query-len'=> 'querylen',
		 'FastaOutput_db'       => 'dbname',
		 'FastaOutput_db-len'   => 'dbsize',

		 'Parameters_matrix'    => { 'param' => 'matrix'},
		 'Parameters_expect'    => { 'param' => 'expect'},
		 'Parameters_include'   => { 'param' => 'include'},
		 'Parameters_sc-match'  => { 'param' => 'match'},
		 'Parameters_sc-mismatch' => { 'param' => 'mismatch'},
		 'Parameters_gap-open'  => { 'param' => 'gapopen'},
		 'Parameters_gap-ext'   => { 'param' => 'gapext'},
		 'Parameters_word-size' => { 'param' => 'wordsize'},
		 'Parameters_ktup'      => { 'param' => 'ktup'},
		 'Parameters_filter'    => {'param' => 'filter'},
		 'Statistics_db-num'    => { 'stat' => 'dbnum'},
		 'Statistics_db-len'    => { 'stat' => 'dblength'},
		 'Statistics_hsp-len'   => { 'stat' => 'hsplength'},
		 'Statistics_eff-space' => { 'stat' => 'effectivespace'},
		 'Statistics_kappa'     => { 'stat' => 'kappa' },
		 'Statistics_lambda'    => { 'stat' => 'lambda' },
		 'Statistics_entropy'   => { 'stat' => 'entropy'},
		 );
}


@ISA = qw(Bio::SearchIO );

=head2 new

 Title   : new
 Usage   : my $obj = new Bio::SearchIO::fasta();
 Function: Builds a new Bio::SearchIO::fasta object 
 Returns : Bio::SearchIO::fasta
 Args    :


=cut

sub new {
  my($class,@args) = @_;

  my $self = $class->SUPER::new(@args);
  
}

=head2 next_report

 Title   : next_report
 Usage   : my $subject = $searchio->next_report;
 Function: Returns the next Report from a search
 Returns : Bio::Search::ReportI object
 Args    : none

=cut

sub next_report{
   my ($self) = @_;
   
   my $data = '';
   my $seentop = 0;
   
   $self->start_document();
   
   while( defined ($_ = $self->_readline )) {
       next if( /^\s+$/); # skip empty lines
       if( /([T]?FAST[AXYF]) searches a protein or DNA sequence/i ) {
	   if( $seentop ) {
	       $self->_pushback($_);
	       $self->end_element({ 'Name' => 'FastaOutput'});
	       return $self->end_document();
	   }
	   $self->{'_reporttype'} = $1;
	   $self->start_element({ 'Name' => 'FastaOutput' } );

	   $seentop = 1;
	   
	   $self->element({ 'Name' => 'FastaOutput_program',
			    'Data' => $self->{'_reporttype'}});
	   $_ = $self->_readline();
	   my ($version) = (/version\s+(\S+)/);
	   $version = '' unless defined $version;
	   $self->element({ 'Name' => 'FastaOutput_version',
			    'Data' => $version});
	   my $last;
	   while( defined($_ = $self->_readline()) ) {
	       if( />(.+)/ ) {
		   my $querydef = $1;
		   my ($len) = ($last =~ /:\s*(\d+)\s+(aa|nt)/);
		   $self->element({'Name' => 'FastaOutput_query-def',
				   'Data' => $querydef});
		   $self->element({'Name' => 'FastaOutput_query-len',
				   'Data' => $len});
		   last;
	       }
	       $last = $_;
	   }	   
	   $_ = $self->_readline();
	   my ($lib) = (/vs\s+(\S+)/);
	   $self->element({'Name' => 'FastaOutput_db',
			   'Data' => $lib});
       } elsif( /(\d+) residues in\s+(\d+)\s+sequences/ ) {
	   $self->element({'Name' => 'FastaOutput_db-len',
			   'Data' => $1});
	   $self->element({'Name' => 'Statistics_db-len',
			   'Data' => $1});
	   $self->element({'Name' => 'Statistics_db-num',
			   'Data' => $2});	   
       } elsif( /Lambda=\s+(\S+)/ ) {
	   $self->element({'Name' => 'Statistics_lambda',
			   'Data' => $1});	  
       } elsif( /^([T]?FAST[XYAF]).+(\S+)\s*matrix.+ktup:\s*(\d+)/ ) {
	   $self->element({'Name' => 'Parameters_matrix',
			   'Data' => $2});
	   $self->element({'Name' => 'Parameters_ktup',
			   'Data' => $3});
	   $self->{'_reporttype'} = $1;

	   $self->element({ 'Name' => 'FastaOutput_program',
			    'Data' => $self->{'_reporttype'}});
	   
       } elsif( /gap\-pen:\s+([\-\+]?\d+)\/\s+([\-\+]?\d+).+width:\s+(\d+)/ ) {
	   $self->element({'Name' => 'Parameters_gap-open',
			   'Data' => $1});
	   $self->element({'Name' => 'Parameters_gap-ext',
			   'Data' => $2});
	   $self->element({'Name' => 'Parameters_word-size',
			   'Data' => $3});
       } elsif( />>(.+) \((\d+)\s*(aa|nt)\)$/ ) {
	   if( $self->in_element('hsp') ) {
	       $self->end_element({ 'Name' => 'Hsp'});
	   }
	   if( $self->in_element('subject') ) {
	       $self->end_element({ 'Name' => 'Hit'});
	   }
	   
	   $self->start_element({'Name' => 'Hit'});
	   $self->element({ 'Name' => 'Hit_len',
			    'Data' => $2});  
	   my ($id,$desc) = split(/\s+/,$1,2);
	   $self->element({ 'Name' => 'Hit_id',
			    'Data' => $id}); 

	   my @pieces = split(/\|/,$id);
	   my $acc = pop @pieces;
	   $acc =~ s/\.\d+$//;
	   $self->element({ 'Name' =>  'Hit_accession',
			    'Data'  => $acc});	
	   $self->element({ 'Name' => 'Hit_def',
			    'Data' => $desc});	   
	   $self->start_element({'Name' => 'Hsp'});
	   $_ = $self->_readline();
	   my ($score,$bits,$e) = ( /Z-score:\s*(\S+)\s*bits:\s*(\S+)\s+E\(\):\s*(\S+)/ );
	   $self->element({'Name' => 'Hsp_score',
			   'Data' => $score});
	   $self->element({'Name' => 'Hsp_evalue',
			   'Data' => $e});
	   $self->element({'Name' => 'Hsp_bit-score',
			   'Data' => $bits});
	   $_ = $self->_readline();
	   if( /Smith-Waterman score:\s*(\d+)/ ) {
	       $self->element({'Name' => 'Hsp_sw-score',
			       'Data' => $1});
	   }
	   if( /(\d+\.\d+)\%\s*identity\s*\((\d+\.\d+)\%\s*ungapped\)\s*in\s*(\d+)\s+(aa|nt)\s+overlap\s*\((\d+)\-(\d+):(\d+)\-(\d+)\)/ ) {
	       my ($identper,$gapper,$len,$querystart,
		   $queryend,$hitstart,$hitend) = ($1,$2,$3,$5,$6,$7,$8);
	       my $ident = POSIX::ceil(($identper/100) * $len);
	       my $gaps = POSIX::ceil ( ($gapper/100) * $len);
	       
	       $self->element({'Name' => 'Hsp_gaps',
			       'Data' => $gaps});
	       $self->element({'Name' => 'Hsp_identity',
			       'Data' => $ident});
#	       $self->element({'Name' => 'Hsp_positive',
#			       'Data' => $ident});
	       $self->element({'Name' => 'Hsp_align-len',
			       'Data' => $len});
	       
	       $self->element({'Name' => 'Hsp_query-from',
			       'Data' => $querystart});
	       $self->element({'Name' => 'Hsp_query-to',
			       'Data' => $queryend});
	       $self->element({'Name' => 'Hsp_hit-from',
			       'Data' => $hitstart});
	       $self->element({'Name' => 'Hsp_hit-to',
			       'Data' => $hitend});
	   } else {
	       $self->warn( "unable to parse FASTA score line: $_");
	   }
       } elsif( /\d+\s*residues\s*in\s*\d+\s*query\s*sequences/ ) {
	   if( $self->in_element('hsp') ) {
	       $self->end_element({'Name' => 'Hsp'});
	   } 
	   if( $self->in_element('subject') ) {
	       $self->end_element({'Name' => 'Hit'});
	   }
	   
#	   $_ = $self->_readline();
#	   my ( $liblen,$libsize) = /(\d+)\s+residues\s*in(\d+)\s*library/;
	   # fast forward to the end of the file as there is 
	   # nothing else left to do with this file and want to be sure and
	   # reset it
	   while(defined($_ = $self->_readline() ) ) { }
	   $self->end_element({ 'Name' => 'FastaOutput'});
	   return $self->end_document();
       } elsif( $self->in_element('hsp' ) ) {
	   
	   my @data = ( '','','');
	   my $count = 0;
	   my $len = 0;
	   while( defined($_ ) ) {
	       chomp;
	       if( $count == 1 || $count == 3 ) {
		   if( /^(\S+\s+)(\S+)/ ) {
		       $len = length($1);
		       $data[$count-1] = $2;
		   } else {
		       $self->warn("Unrecognized alignment line $_");
		   }
	       } elsif( $count == 2 ) {
		   # toss the first 7 characters of the line
		   $data[$count-1] = substr($_,7);
	       }
	       last if( $count++ >= 5);
	       $_ = $self->_readline();
	   }
	   $self->characters({'Name' => 'Hsp_qseq',
			      'Data' => $data[0] });
	   $self->characters({'Name' => 'Hsp_midline',
			      'Data' => $data[1]});
	   $self->characters({'Name' => 'Hsp_hseq',
			      'Data' => $data[2]});

       } else {
	   if( ! $seentop ) {
	       print;
	       
	       $self->warn("unrecognized FASTA report file!");
	       return undef;
	   }
       }
   }
}


=head2 start_element

 Title   : start_element
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub start_element{
   my ($self,$data) = @_;
    # we currently don't care about attributes
    my $nm = $data->{'Name'};    
    if( my $type = $MODEMAP{$nm} ) {
	$self->_mode($type);
	if( $self->_eventHandler->will_handle($type) ) {
	    my $func = sprintf("start_%s",lc $type);
	    $self->_eventHandler->$func($data->{'Attributes'});
	}						 
	unshift @{$self->{'_elements'}}, $type;
    }
    if($nm eq 'FastaOutput') {
	$self->{'_values'} = {};
	$self->{'_report'}= undef;
	$self->{'_mode'} = '';
    }

}

=head2 end_element

 Title   : end_element
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub end_element {
    my ($self,$data) = @_;
    my $nm = $data->{'Name'};
    my $rc;
    # Hsp are sort of weird, in that they end when another
    # object begins so have to detect this in end_element for now
    if( $nm eq 'Hsp' ) {
	foreach ( qw(Hsp_qseq Hsp_midline Hsp_hseq) ) {
	    $self->element({'Name' => $_,
			    'Data' => $self->{'_last_hspdata'}->{$_}});
	}
	$self->{'_last_hspdata'} = {}
    }

    if( my $type = $MODEMAP{$nm} ) {
	if( $self->_eventHandler->will_handle($type) ) {
	    my $func = sprintf("end_%s",lc $type);
	    $rc = $self->_eventHandler->$func($self->{'_reporttype'},
					      $self->{'_values'});	    
	}
	shift @{$self->{'_elements'}};

    } elsif( $MAPPING{$nm} ) { 	
	if ( ref($MAPPING{$nm}) =~ /hash/i ) {
	    my $key = (keys %{$MAPPING{$nm}})[0];	    
	    $self->{'_values'}->{$key}->{$MAPPING{$nm}->{$key}} = $self->{'_last_data'};
	} else {
	    $self->{'_values'}->{$MAPPING{$nm}} = $self->{'_last_data'};
	}
    } else { 
	print "unknown nm $nm, ignoring\n";
    }
    $self->{'_last_data'} = ''; # remove read data if we are at 
				# end of an element
    $self->{'_report'} = $rc if( $nm eq 'FastaOutput' );
    return $rc;

}

=head2 element

 Title   : element
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub element{
   my ($self,$data) = @_;
   $self->start_element($data);
   $self->characters($data);
   $self->end_element($data);
}


=head2 characters

 Title   : characters
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub characters{
   my ($self,$data) = @_;   

   if( $self->in_element('hsp') && 
       $data->{'Name'} =~ /Hsp\_(qseq|hseq|midline)/ ) {
       $self->{'_last_hspdata'}->{$data->{'Name'}} .= $data->{'Data'};
   }  
   return unless ( defined $data->{'Data'} && $data->{'Data'} !~ /^\s+$/ );
   
   $self->{'_last_data'} = $data->{'Data'}; 
}

=head2 _mode

 Title   : _mode
 Usage   : $obj->_mode($newval)
 Function: 
 Example : 
 Returns : value of _mode
 Args    : newvalue (optional)


=cut

sub _mode{
    my ($self,$value) = @_;
    if( defined $value) {
	$self->{'_mode'} = $value;
    }
    return $self->{'_mode'};
}

=head2 in_element

 Title   : in_element
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub in_element{
    my ($self,$name) = @_;  
    return 0 if( scalar @{$self->{'_elements'}} == 0 ) ;
    return ( $self->{'_elements'}->[0] eq $name);
}

=head2 start_document

 Title   : start_document
 Usage   : 
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub start_document{
    my ($self) = @_;
    $self->{'_lasttype'} = '';
    $self->{'_values'} = {};
    $self->{'_report'}= undef;
    $self->{'_mode'} = '';
    $self->{'_elements'} = [];
}

=head2 end_document

 Title   : end_document
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub end_document{
   my ($self,@args) = @_;
   return $self->{'_report'};
}

1;

