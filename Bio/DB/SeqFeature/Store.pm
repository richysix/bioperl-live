package Bio::DB::SeqFeature::Store;
use strict;

use base 'Bio::SeqFeature::CollectionI';
use Carp 'croak';
use Bio::DB::GFF::Util::Rearrange;
use Bio::DB::SeqFeature::Segment;
use Scalar::Util 'blessed';

*dna = *get_dna = *get_sequence = \&fetch_sequence;
*get_SeqFeatures = \&fetch_SeqFeatures;

###
# object constructor
#
sub new {
  my $self      = shift;
  my ($adaptor,$serializer,$index_subfeatures,$args);
  if (@_ == 1) {
    $args = {DSN => shift}
  }
  else {
    ($adaptor,$serializer,$index_subfeatures,$args) =
      rearrange(['ADAPTOR',
		 'SERIALIZER',
		 'INDEX_SUBFEATURES'
		],@_);
  }
  $adaptor ||= 'DBI::mysql';

  my $class = "Bio::DB::SeqFeature::Store::$adaptor";
  eval "require $class " or croak $@;
  my $obj = $class->new_instance();
  $obj->init($args);
  $obj->serializer($serializer)               if defined $serializer;
  $obj->index_subfeatures($index_subfeatures) if defined $index_subfeatures;
  $obj;
}

sub new_instance {
  my $class = shift;
  return bless {},ref($class) || $class;
}

sub init {
  my $self = shift;
  $self->default_settings();
}

sub debug {
  my $self = shift;
  my $d = $self->{debug};
  $self->{debug} = shift if @_;
  $d;
}

###
# default settings -- set up whatever are the proper default settings
#
sub default_settings {
  my $self = shift;
  $self->serializer($self->default_serializer);
  $self->index_subfeatures(1);
}

###
# choose a serializer
#
sub default_serializer {
  my $self = shift;
  # try Storable
  eval "require Storable; 1"     and return 'Storable';
  eval "require Data::Dumper; 1" and return 'Data::Dumper';
  croak "Unable to load either Storable or Data::Dumper. Please provide a serializer using -serializer";
}

# persistent settings
# by default we store in the object
sub setting {
  my $self  = shift;
  my $variable_name = shift;
  my $d    = $self->{setting}{$variable_name};
  $self->{setting}{$variable_name} = shift if @_;
  $d;
}

###
# serializer
#
sub serializer {
  my $self = shift;
  my $d    = $self->setting('serializer');
  if (@_) {
    my $serializer = shift;
    eval "require $serializer; 1" or croak $@;
    $self->setting(serializer=>$serializer);
    $Storable::forgive_me =1 if $serializer eq 'Storable';
  }
  $d;
}

###
# whether subfeatures are all indexed
#
sub subfeatures_are_indexed {
  my $self = shift;
  my $d    = $self->setting('subfeatures_are_indexed');
  $self->setting(subfeatures_are_indexed => shift) if @_;
  $d;
}

###
# whether to index subfeatures by default
#
sub index_subfeatures {
  my $self = shift;
  my $d    = $self->setting('index_subfeatures');
  $self->setting('index_subfeatures'=>shift) if @_;
  $d;
}

###
# wipe database clean and reinstall schema
#
sub init_database {
  my $self = shift;
  $self->_init_database(@_);
}

###
# store one or more Bio::SeqFeatureI objects
#      if they already have a primary_id will replace into the database
#      otherwise will insert and primary_id will be added
#

# this version stores the object and flags it to be indexed
# for search via attributes, name, type or location

sub store {
  my $self = shift;
  $self->_store(1,@_);
}

# this version stores the object and flags it so that it is
# not searchable via attributes, name, type or location
# (typically used only for subfeatures)
sub store_noindex {
  my $self = shift;
  $self->_store(0,@_);
}

sub delete {
  my $self   = shift;
  my $object = shift;
  my $id = $object->primary_id;
  $self->_deleteid($id);
}

###
# Add a subparts to a feature. Both feature and all subparts must already be in database.
#
sub add_SeqFeature {
  my $self     = shift;
  my $parent   = shift;
  my @children = @_;

  $self->_add_SeqFeature($parent,@children);
}

sub fetch_SeqFeatures {
  my $self   = shift;
  my $parent = shift;
  my @types  = @_;
  $self->_add_SeqFeatures($parent,@types);
}

###
# Fetch a Bio::SeqFeatureI from database using its primary_id
#
sub fetch {
  my $self       = shift;
  @_ or croak "usage: fetch(\$primary_id)";
  my $primary_id = shift;
  $self->_fetch($primary_id);
}

sub update {
  my $self = shift;
  my $object = shift;
  defined (my $primary_id = eval { $object->primary_id})
    or $self->throw("$object has no primary ID: $@");
  $self->_update($object,$primary_id);
}

###
# Efficiently fetch a series of IDs from the database
# Can pass an array or an array ref
#
sub fetch_many {
  my $self       = shift;
  @_ or croak 'usage: fetch_many($id1,$id2,$id3...)';
  my @ids = map {ref($_) ? @$_ : $_} @_ or return;
  $self->_fetch_many(@ids);
}

###
# Return an iterator across all features that are indexable
#
sub get_seq_stream {
  my $self = shift;
  $self->_features(-iterator=>1,@_);
}

###
# Replacement for Bio::DB::GFF->segment() method
#
sub segment {
  my $self = shift;
  my (@features,@args);

  if (@_ == 1 && blessed($_[0])) {
    @features = @_;
    @args = ();
  }
  else {
    @args     = $self->setup_segment_args(@_);
    @features = $self->get_features_by_name(@args);
  }
  if (!wantarray && @features > 1) {
    $self->throw(<<END);
segment() called in a scalar context but multiple features match.
Either call in a list context or narrow your search using the -types or -class arguments
END
  }
  my ($rel_start,$rel_end) = rearrange(['START',['STOP','END']],@args);
  $rel_start = 1 unless defined $rel_start;

  my @segments;
  for my $f (@features) {
    my $seqid  = $f->seq_id;
    my $strand = $f->strand;
    my ($start,$end);
    $rel_end = $f->end - $f->start + 1 unless defined $rel_end;

    if ($strand >= 0) {
      $start = $f->start + $rel_start - 1;
      $end   = $f->start + $rel_end   - 1;
    }
    else {
      $start = $f->end - $rel_end   + 1;
      $end   = $f->end - $rel_start + 1;
    }
    push @segments,Bio::DB::SeqFeature::Segment->new($self,$seqid,$start,$end,$strand);
  }
  return wantarray ? @segments : $segments[0];
}

sub setup_segment_args {
  my $self = shift;
  return @_ if defined $_[0] && $_[0] =~ /^-/;
  return (-name=>$_[0],-start=>$_[1],-end=>$_[2]) if @_ == 3;
  return (-class=>$_[0],-name=>$_[1])              if @_ == 2;
  return (-name=>$_[0])                            if @_ == 1;
  return;
}

# backward compatibility for gbrowse
sub get_feature_by_name { shift->get_features_by_name(@_) }

###
# get_feature_by_name() return 0 or more features using a name lookup
# uses the Bio::DB::GFF API
#
sub get_features_by_name {
  my $self   = shift;
  my ($class,$name,$types,$allow_alias);

  if (@_ == 1) {  # get_features_by_name('name');
    $name = shift;
  } else {        # get_features_by_name('class'=>'name'), get_feature_by_name(-name=>'name')
    ($class,$name,$allow_alias,$types) = rearrange([qw(CLASS NAME ALIASES),[qw(TYPE TYPES)]],@_);
  }

  # hacky workaround for assumption in Bio::DB::GFF that unclassed reference points were of type "Sequence"
  undef $class if $class && $class eq 'Sequence';

  $self->_features(-name=>$name,-class=>$class,-aliases=>$allow_alias,-type=>$types);
}

sub get_features_by_alias {
  my $self = shift;
  my @args = @_;
  if (@_ == 1) {
    @args  = (-name=>shift);
  }
  push @args,(-aliases=>1);
  $self->get_features_by_name(@args);
}

sub get_features_by_type {
  my $self = shift;
  my $type = shift;
  $self->_features(-type=>$type);
}

sub get_features_by_location {
  my $self = shift;
  my ($seqid,$start,$end,$strand,$rangetype) = 
    rearrange([['SEQ_ID','SEQID','REF'],'START',['STOP','END'],'STRAND','RANGE_TYPE'],@_);
  $self->_features(-seqid=>$seqid,
		   -start=>$start||undef,
		   -end=>$end||undef,
		   -strand=>$strand||undef,
		   -range_type=>$rangetype);
}

sub get_features_by_attribute {
  my $self       = shift;
  my $attributes = shift;
  $attributes  or croak "Usage: get_feature_by_attribute({attribute_hash})";
  $self->_features(-attributes=>$attributes);
}
###
# features() call -- main query interface
#

# documentation of args
#   my ($seq_id,$start,$end,$strand,
#       $name,$class,$allow_aliases,
#       $types,
#       $attributes,
#       $range_type,
#       $iterator,
#      ) = rearrange([['SEQID','SEQ_ID','REF'],'START',['STOP','END'],'STRAND',
# 		    'NAME','CLASS','ALIASES',
# 		    ['TYPES','TYPE','PRIMARY_TAG'],
# 		    ['ATTRIBUTES','ATTRIBUTE'],
# 		    'RANGE_TYPE',
# 		   ],@_);
#   $range_type ||= 'overlaps';
sub features {
  my $self = shift;
  my @args;
  if (@_ == 1) {
    @args = (-type=>shift);
  } else {
    @args = @_;
  }
  $self->_features(@args);
}

###
# search_notes()
#
sub search_notes {
  my $self = shift;
  my ($search_string,$limit) = @_;
  return $self->_search_notes($search_string,$limit);
}

###
# insert_sequence()
#
# insert a bit of primary sequence into the database
#
sub insert_sequence {
  my $self = shift;
  my ($seqid,$offset,$seq) = @_;
  $self->_insert_sequence($seqid,$offset,$seq);
}

###
# get_sequence()
#
# equivalent to old Bio::DB::GFF->dna() method
#
sub fetch_sequence {
  my $self = shift;
  my ($seqid,$start,$end,$class) = rearrange([['NAME','SEQID','SEQ_ID'],'START',['END','STOP'],'CLASS'],@_);
  $seqid = "$seqid:$class" if defined $class;
  $self->_fetch_sequence($seqid,$start,$end);
}

###
# force reindexing
#
sub reindex {
  my $self = shift;

  my $count = 0;
  my $now;
  my $last_time = time();

  $self->_start_reindexing;

  my $iterator = $self->get_seq_stream;
  while (my $f = $iterator->next_seq) {
    if (++$count %1000 == 0) {
      $now = time();
      my $elapsed = sprintf(" in %5.2fs",$now - $last_time);
      $last_time = $now;
      print STDERR "$count features indexed$elapsed...",' 'x60;
      print STDERR -t STDOUT && !$ENV{EMACS} ? "\r" : "\n";
    }
    $self->_update_indexes($f);
  }

  $self->_end_reindexing;
}

sub _load_class {
  my $self = shift;
  my $obj  = shift;
  return if $self->{class_loaded}{ref $obj}++;
  unless ($obj && $obj->can('primary_id')) {
    my $class = ref $obj;
    eval "require $class";
  }
}

sub start_bulk_update  { shift->_start_bulk_update(@_) }
sub finish_bulk_update { shift->_finish_bulk_update(@_) }


################################# TIE interface ####################

sub TIEHASH {
  my $class = shift;
  return $class->new(@_);
}

sub STORE {
  my $self = shift;
  my ($key,$feature) = @_;
  $key =~ /^\d+$/ && $key > 0 or croak "keys must be positive integers";
  $self->_load_class($feature);
  $feature->primary_id($key);
  $self->store($feature);
}

sub FETCH {
  my $self = shift;
  $self->fetch(@_);
}

sub FIRSTKEY {
  my $self = shift;
  $self->_firstid;
}

sub NEXTKEY {
  my $self    = shift;
  my $lastkey = shift;
  $self->_nextid($lastkey);
}

sub EXISTS {
  my $self = shift;
  my $key  = shift;
  $self->existsid($key);
}

sub DELETE {
  my $self = shift;
  my $key  = shift;
  $self->_deleteid($key);
}

sub CLEAR {
  my $self = shift;
  $self->_clearall;
}

sub SCALAR {
  my $self = shift;
  $self->_featurecount;
}

###################### TO BE IMPLEMENTED BY ADAPTOR ##########

# DOC THIS!!!!!
sub _new { shift->throw_not_implemented}

sub _init_database { shift->throw_not_implemented }

# _store($indexed,@objs)
sub _store {
  my $self    = shift;
  my $indexed = shift;
  my @objs    = @_;
  $self->throw_not_implemented;
}

# _store($indexed,@objs)
sub _update {
  my $self       = shift;
  my $object     = shift;
  my $primary_id = shift;
  $self->throw_not_implemented;
}

# this is called to index a feature
sub _update_indexes { shift->throw_not_implemented }

# these do not necessary have to be overridden
# they are called at beginning and end of reindexing process
sub _start_reindexing {}
sub _end_reindexing   {}

# _fetch($id)
sub _fetch { shift->throw_not_implemented }

# _fetch_many(@ids)
# this one will fall back to many calls on fetch() if you don't
# override it
sub _fetch_many {
  my $self = shift;
  return map {$self->_fetch($_)} @_;
}

# bottleneck query generator
sub _features { shift->throw_not_implemented }

sub _search_notes { shift->throw_not_implemented }

# return true here if the storage engine is prepared to store parent/child
# relationships using _add_SeqFeature and return them using _fetch_SeqFeatures
sub can_store_parentage { return; }

# these two are called only if _can_store_subFeatures() returns true
# _add_SeqFeature ($parent,@children)
sub _add_SeqFeature { shift->throw_not_implemented }

# _get_SeqFeatures($parent,@list_of_child_types)
sub _fetch_SeqFeatures {shift->throw_not_implemented }

# _fetch_sequence() is similar to old dna() method
sub _insert_sequence { shift->throw_not_implemented }
sub _fetch_sequence    { shift->throw_not_implemented }

# for full TIE() interface  - not necessary to implement in most cases
sub _firstid  { shift->throw_not_implemented }
sub _nextid   { shift->throw_not_implemented }
sub _existsid { shift->throw_not_implemented }
sub _deleteid { shift->throw_not_implemented }
sub _clearall { shift->throw_not_implemented }
sub _featurecount { shift->throw_not_implemented }

# Optional flags to change behavior to optimize bulk updating.
sub _start_bulk_update { }
sub _finish_bulk_update { }

#################################### Internal methods ####################

sub _freeze {
  my $self = shift;
  my $obj  = shift;

  # Bio::SeqFeature::Generic contains cleanup methods, so we need to
  # localize the methods to undef temporarily so that we can serialize
  local $obj->{'_root_cleanup_methods'} if exists $obj->{'_root_cleanup_methods'};

  my ($id,$store);
  $id    = $obj->primary_id();
  $obj->primary_id(undef);     # don't want primary ID to be stored in object
  eval {
    $store = $obj->object_store;
    $obj->object_store(undef);   # don't want a copy of the store in the object
  };
  my $serializer = $self->serializer;
  my $data;
  if ($serializer eq 'Data::Dumper') {
    my $d    = Data::Dumper->new([$obj]);
    $d->Terse(1);
    $d->Deepcopy(1);
    $data = $d->Dump;
  } elsif ($serializer eq 'Storable') {
    $data = Storable::freeze($obj);
  }

  $obj->primary_id($id);       # restore to original state
  eval {
    $obj->object_store($store);
  };

  return $data;
}

sub _thaw {
  my $self               = shift;
  my ($obj,$primary_id)  = @_;
  my $serializer = $self->serializer;
  my $object;
  if ($serializer eq 'Data::Dumper') {
    $object = $obj;
  } elsif ($serializer eq 'Storable') {
    $object = Storable::thaw($obj);
  }

  # remember the primary ID of this object as well as the
  # identity of the store, so that we can do lazy loading;
  # both of these are wrapped in an eval because not all
  # bioseqfeatures support them (or want to)
  $self->_load_class($object);
  eval {
    $object->primary_id($primary_id);
    $object->object_store($self);
  };
  $object;
}

1;