package MediaWords::Languages::Language;

#
# Generic language plug-in for Media Words, also a factory of configured + enabled languages.
#
# Has to be overloaded by a specific language plugin (think of this as an abstract class).
#
# See doc/README.languages for instructions.
#

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;
use utf8;

use Moose::Role;
use Lingua::Stem::Snowball;
use Lingua::StopWords;
use Lingua::Sentence;
use Locale::Country::Multilingual { use_io_layer => 1 };
use MediaWords::Util::IdentifyLanguage;    # to check if the language can be identified

use File::Basename ();
use Cwd            ();

#
# LIST OF ENABLED LANGUAGES
#
my Readonly @enabled_languages = (
    'da',                                  # Danish
    'de',                                  # German
    'en',                                  # English
    'es',                                  # Spanish
    'fi',                                  # Finnish
    'fr',                                  # French
    'hu',                                  # Hungarian
    'it',                                  # Italian
    'lt',                                  # Lithuanian
    'nl',                                  # Dutch
    'no',                                  # Norwegian
    'pt',                                  # Portuguese
    'ro',                                  # Romanian
    'ru',                                  # Russian
    'sv',                                  # Swedish
    'tr',                                  # Turkish
    'zh',                                  # Chinese
);

#
# START OF THE SUBCLASS INTERFACE
#

# Returns a string ISO 639-1 language code (e.g. 'en')
requires 'get_language_code';

# Returns a hashref to a "tiny" (~200 entries) list of stop words for the language
# where the keys are all stopwords and the values are all 1.
#
# If Lingua::StopWords module supports the language you're about to add, you can use the module helper:
#
#   sub fetch_and_return_tiny_stop_words
#   {
#       my $self = shift;
#       return $self->_get_stop_words_with_lingua_stopwords( 'en', 'UTF-8' );
#   }
#
# If you've decided to store a stoplist in an external file, you can use the module helper:
#
#   sub fetch_and_return_tiny_stop_words
#   {
#       my $self = shift;
#       return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/en_stoplist_tiny.txt' );
#   }
#
requires 'fetch_and_return_tiny_stop_words';

# Returns a hashref to a "short" (~1000 entries) list of stop words for the language
# where the keys are all stopwords and the values are all 1.
# Also see a description of the available helpers above.
requires 'fetch_and_return_short_stop_words';

# Returns a hashref to a "long" (~4000+ entries) list of stop words for the language
# where the keys are all stopwords and the values are all 1.
# Also see a description of the available helpers above.
requires 'fetch_and_return_long_stop_words';

# Returns a reference to an array of stemmed words (using Lingua::Stem::Snowball or some other way)
# A parameter is an array.
#
# If Lingua::Stem::Snowball module supports the language you're about to add, you can use the module helper:
#
#   sub stem
#   {
#       my $self = shift;
#       return $self->_stem_with_lingua_stem_snowball( 'fr', 'UTF-8', \@_ );
#   }
#
requires 'stem';

# Returns a word length limit of a language (0 -- no limit)
requires 'get_word_length_limit';

# Returns a list of sentences from a story text (tokenizes text into sentences)
requires 'get_sentences';

# Returns a reference to an array with a tokenized sentence for the language
#
# If the words in a sentence are separated by spaces (as with most of the languages with
# a Latin-derived alphabet), you can use the module helper:
#
#   sub tokenize
#   {
#       my ( $self, $sentence ) = @_;
#       return $self->_tokenize_with_spaces( $sentence );
#   }
#
requires 'tokenize';

# Returns an object complying with Locale::Codes::API "protocol" (e.g. an instance of
# Locale::Country::Multilingual) for fetching a list of country codes and countries.
requires 'get_locale_codes_api_object';

#
# END OF THE SUBCLASS INTERFACE
#

# Lingua::Stem::Snowball instance (if needed), lazy-initialized in _stem_with_lingua_stem_snowball()
has 'stemmer' => ( is => 'rw', default => 0 );

# Lingua::Stem::Snowball language and encoding
has 'stemmer_language' => ( is => 'rw', default => 0 );
has 'stemmer_encoding' => ( is => 'rw', default => 0 );

# Lingua::Sentence instance (if needed), lazy-initialized in _tokenize_text_with_lingua_sentence()
has 'sentence_tokenizer' => ( is => 'rw', default => 0 );

# Lingua::Sentence language
has 'sentence_tokenizer_language' => ( is => 'rw', default => 0 );

# Instance of Locale::Country::Multilingual (if needed), lazy-initialized in _get_locale_country_multilingual_object()
has 'locale_country_multilingual_object' => ( is => 'rw', default => 0 );

# Cached stopwords
has 'cached_tiny_stop_words'  => ( is => 'rw', default => 0 );
has 'cached_short_stop_words' => ( is => 'rw', default => 0 );
has 'cached_long_stop_words'  => ( is => 'rw', default => 0 );

# Cached stopword stems
has 'cached_tiny_stop_word_stems'  => ( is => 'rw', default => 0 );
has 'cached_short_stop_word_stems' => ( is => 'rw', default => 0 );
has 'cached_long_stop_word_stems'  => ( is => 'rw', default => 0 );

# Instances of each of the enabled languages (e.g. MediaWords::Languages::en, MediaWords::Languages::lt, ...)
my %_lang_instances;

# Load enabled language modules
foreach my $language_to_load ( @enabled_languages )
{

    # Check if the language is supported by the language identifier
    if ( !MediaWords::Util::IdentifyLanguage::language_is_supported( $language_to_load ) )
    {
        die(
            "Language module '$language_to_load' is enabled but the language is not supported by the language identifier." );
    }

    # Load module
    my $module = 'MediaWords::Languages::' . $language_to_load;
    eval {
        ( my $file = $module ) =~ s|::|/|g;
        require $file . '.pm';
        $module->import();
        1;
    } or do
    {
        my $error = $@;
        die( "Error while loading module for language '$language_to_load': $error" );
    };

    # Initialize an instance of the particular language module
    $_lang_instances{ $language_to_load } = $module->new();
}

# (static) Returns 1 if language is enabled, 0 if not
sub language_is_enabled($)
{
    my $language_code = shift;

    if ( exists $_lang_instances{ $language_code } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# (static) Returns language module instance for the language code, 0 on error
sub language_for_code($)
{
    my $language_code = shift;

    if ( !language_is_enabled( $language_code ) )
    {
        return 0;
    }

    return $_lang_instances{ $language_code };
}

# (static) Returns default language module instance (English)
sub default_language
{
    my $language = language_for_code { default_language_code() };
    if ( $language )
    {
        die "Default language 'en' is not enabled.";
    }

    return $language;
}

# (static) Returns default language code ('en' for English)
sub default_language_code
{
    return 'en';
}

# Cached stop words
sub get_tiny_stop_words
{
    my $self = shift;

    if ( $self->cached_tiny_stop_words == 0 )
    {
        $self->cached_tiny_stop_words( $self->fetch_and_return_tiny_stop_words() );
    }

    return $self->cached_tiny_stop_words;
}

sub get_short_stop_words
{
    my $self = shift;

    if ( $self->cached_short_stop_words == 0 )
    {
        $self->cached_short_stop_words( $self->fetch_and_return_short_stop_words() );
    }

    return $self->cached_short_stop_words;
}

sub get_long_stop_words
{
    my $self = shift;

    if ( $self->cached_long_stop_words == 0 )
    {
        $self->cached_long_stop_words( $self->fetch_and_return_long_stop_words() );
    }

    return $self->cached_long_stop_words;
}

# Get stop word stems
sub get_tiny_stop_word_stems
{
    my $self = shift;

    if ( $self->cached_tiny_stop_word_stems == 0 )
    {
        my $stems = [ keys( %{ $self->get_tiny_stop_words() } ) ];
        my $hash;

        $stems = $self->stem( @{ $stems } );

        for my $stem ( @{ $stems } )
        {
            $hash->{ $stem } = 1;
        }

        $self->cached_tiny_stop_word_stems( $hash );
    }

    return $self->cached_tiny_stop_word_stems;
}

sub get_short_stop_word_stems
{
    my $self = shift;

    if ( $self->cached_short_stop_word_stems == 0 )
    {
        my $stems = [ keys( %{ $self->get_short_stop_words() } ) ];
        my $hash;

        $stems = $self->stem( @{ $stems } );

        for my $stem ( @{ $stems } )
        {
            $hash->{ $stem } = 1;
        }

        $self->cached_short_stop_word_stems( $hash );
    }

    return $self->cached_short_stop_word_stems;
}

sub get_long_stop_word_stems
{
    my $self = shift;

    if ( $self->cached_long_stop_word_stems == 0 )
    {
        my $stems = [ keys( %{ $self->get_long_stop_words() } ) ];
        my $hash;

        $stems = $self->stem( @{ $stems } );

        for my $stem ( @{ $stems } )
        {
            $hash->{ $stem } = 1;
        }

        $self->cached_long_stop_word_stems( $hash );
    }

    return $self->cached_long_stop_word_stems;
}

# Returns an instance of Locale::Country::Multilingual for the language code
sub _get_locale_country_multilingual_object
{
    my ( $self, $language ) = @_;

    if ( $self->locale_country_multilingual_object == 0 )
    {
        $self->locale_country_multilingual_object( Locale::Country::Multilingual->new() );
        $self->locale_country_multilingual_object->set_lang( $language );
    }

    return $self->locale_country_multilingual_object;
}

# Lingua::Stem::Snowball helper
sub _stem_with_lingua_stem_snowball
{
    my ( $self, $language, $encoding, $ref_words ) = @_;

    # (Re-)initialize stemmer if needed
    if ( $self->stemmer == 0 or $self->stemmer_language ne $language or $self->stemmer_encoding ne $encoding )
    {
        $self->stemmer(
            Lingua::Stem::Snowball->new(
                lang     => $language,
                encoding => $encoding
            )
        );
    }

    my @stems = $self->stemmer->stem( $ref_words );

    return \@stems;
}

# Lingua::StopWords helper
sub _get_stop_words_with_lingua_stopwords
{
    my ( $self, $language, $encoding ) = @_;
    return Lingua::StopWords::getStopWords( $language, $encoding );
}

# Lingua::Sentence helper
sub _tokenize_text_with_lingua_sentence
{
    my ( $self, $language, $nonbreaking_prefixes_file, $text ) = @_;

    # (Re-)initialize stemmer if needed
    if ( $self->sentence_tokenizer == 0 or $self->sentence_tokenizer ne $language )
    {
        $self->sentence_tokenizer( Lingua::Sentence->new( $language, $nonbreaking_prefixes_file ) );
    }

    # Lingua::Sentence thinks that end-of-line character means the end of the sentence, so
    # replace \n with a space
    $text =~ s/\n/ /gs;
    $text =~ s/  */ /gs;

    my @sentences = $self->sentence_tokenizer->split_array( $text );

    return \@sentences;
}

# Returns the root directory
sub _base_dir
{
    my $relative_path = '../../../';    # Path to base of project relative to the current file
    my $base_dir = Cwd::realpath( File::Basename::dirname( __FILE__ ) . '/' . $relative_path );
    return $base_dir;
}

# Returns stopwords read from a file
sub _get_stop_words_from_file
{
    my ( $self, $filename ) = @_;

    $filename = _base_dir() . '/' . $filename;

    my %stopwords;

    # Read stoplist, ignore comments, ignore empty lines
    use open IN => ':utf8';
    open STOPLIST, $filename or die "Unable to read '$filename': $!";
    while ( my $line = <STOPLIST> )
    {

        # Remove comments
        $line =~ s/\s*?#.*?$//s;

        chomp( $line );

        if ( length( $line ) )
        {
            $stopwords{ $line } = 1;
        }
    }
    close( STOPLIST );

    return \%stopwords;
}

# Converts an array into hashref (for a list of stop words)
sub _array_to_hashref
{
    my $self = shift;
    my %hash = map { $_ => 1 } @_;
    return \%hash;
}

# Tokenizes a sentence with spaces (for Latin languages)
sub _tokenize_with_spaces
{
    my ( $self, $sentence ) = @_;

    my $tokens = [];
    while ( $sentence =~ m~(\w[\w']*)~g )
    {
        push( @{ $tokens }, lc( $1 ) );
    }

    return $tokens;
}

1;
