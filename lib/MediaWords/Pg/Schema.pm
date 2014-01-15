package MediaWords::Pg::Schema;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Languages::Language;
use MediaWords::Util::SchemaVersion;

# import functions into server schema

use strict;
use warnings;

use IPC::Run3;
use Carp;
use FindBin;

# get is_stop_stem() stopword + stopword stem tables and a pl/pgsql function definition
sub get_is_stop_stem_function_tables_and_definition
{
    my $sql = '';

    my @stoplist_sizes = ( 'tiny', 'short', 'long' );

    for my $stoplist_size ( @stoplist_sizes )
    {

        # create tables
        $sql .= <<END

            -- PostgreSQL sends notices about implicit keys that are being created,
            -- and the test suite takes them for warnings.
            SET client_min_messages=WARNING;

            -- "Full" stopwords
            DROP TABLE IF EXISTS stopwords_${stoplist_size};
            CREATE TABLE stopwords_${stoplist_size} (
                stopwords_${stoplist_size}_id SERIAL PRIMARY KEY,
                stopword VARCHAR(256) NOT NULL,
                language VARCHAR(3) NOT NULL /* 2- or 3-character ISO 690 language code */
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopwords_${stoplist_size}_stopword
                ON stopwords_${stoplist_size}(stopword, language);

            -- Stopword stems
            DROP TABLE IF EXISTS stopword_stems_${stoplist_size};
            CREATE TABLE stopword_stems_${stoplist_size} (
                stopword_stems_${stoplist_size}_id SERIAL PRIMARY KEY,
                stopword_stem VARCHAR(256) NOT NULL,
                language VARCHAR(3) NOT NULL /* 2- or 3-character ISO 690 language code */
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopword_stems_${stoplist_size}_stopword_stem
                ON stopword_stems_${stoplist_size}(stopword_stem, language);

            -- Reset the message level back to "notice".
            SET client_min_messages=NOTICE;

END
          ;

        # For every language
        my @enabled_languages = MediaWords::Languages::Language::enabled_languages();
        foreach my $language_code ( @enabled_languages )
        {
            my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
            if ( !$lang )
            {
                die "Language '$language_code' is not enabled.";
            }

            # collect stopwords
            my $stopwords_hashref;
            if ( $stoplist_size eq 'tiny' )
            {
                $stopwords_hashref = $lang->get_tiny_stop_words();
            }
            elsif ( $stoplist_size eq 'short' )
            {
                $stopwords_hashref = $lang->get_short_stop_words();
            }
            elsif ( $stoplist_size eq 'long' )
            {
                $stopwords_hashref = $lang->get_long_stop_words();
            }
            my @stopwords;
            while ( my ( $stopword, $value ) = each %{ $stopwords_hashref } )
            {
                if ( $value == 1 )
                {
                    $stopword =~ s/'/''/;
                    push( @stopwords, "('$stopword', '$language_code')" );
                }
            }

            # collect stopword stems
            my $stopword_stems_hashref;
            if ( $stoplist_size eq 'tiny' )
            {
                $stopword_stems_hashref = $lang->get_tiny_stop_word_stems();
            }
            elsif ( $stoplist_size eq 'short' )
            {
                $stopword_stems_hashref = $lang->get_short_stop_word_stems();
            }
            elsif ( $stoplist_size eq 'long' )
            {
                $stopword_stems_hashref = $lang->get_long_stop_word_stems();
            }
            my @stopword_stems;
            while ( my ( $stopword_stem, $value ) = each %{ $stopword_stems_hashref } )
            {
                if ( $value == 1 )
                {
                    $stopword_stem =~ s/'/''/;
                    push( @stopword_stems, "('$stopword_stem', '$language_code')" );
                }
            }

            # insert stopwords and stopword stems
            $sql .=
              'INSERT INTO stopwords_' . $stoplist_size . ' (stopword, language) VALUES ' . join( ', ', @stopwords ) . ';';
            $sql .= 'INSERT INTO stopword_stems_' . $stoplist_size . ' (stopword_stem, language) VALUES ' .
              join( ', ', @stopword_stems ) . ';';
        }

    }

    # create a function
    $sql .= <<END

        CREATE OR REPLACE FUNCTION is_stop_stem(p_size TEXT, p_stem TEXT, p_language TEXT)
            RETURNS BOOLEAN AS \$\$
        DECLARE
            result BOOLEAN;
        BEGIN

            -- Tiny
            IF p_size = 'tiny' THEN
                IF p_language IS NULL THEN
                    SELECT 't' INTO result FROM stopword_stems_tiny
                        WHERE stopword_stem = p_stem;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                ELSE
                    SELECT 't' INTO result FROM stopword_stems_tiny
                        WHERE stopword_stem = p_stem AND language = p_language;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                END IF;

            -- Short
            ELSIF p_size = 'short' THEN
                IF p_language IS NULL THEN
                    SELECT 't' INTO result FROM stopword_stems_short
                        WHERE stopword_stem = p_stem;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                ELSE
                    SELECT 't' INTO result FROM stopword_stems_short
                        WHERE stopword_stem = p_stem AND language = p_language;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                END IF;

            -- Long
            ELSIF p_size = 'long' THEN
                IF p_language IS NULL THEN
                    SELECT 't' INTO result FROM stopword_stems_long
                        WHERE stopword_stem = p_stem;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                ELSE
                    SELECT 't' INTO result FROM stopword_stems_long
                        WHERE stopword_stem = p_stem AND language = p_language;
                    IF NOT FOUND THEN
                        result := 'f';
                    END IF;
                END IF;

            -- unknown size
            ELSE
                RAISE EXCEPTION 'Unknown stopword stem size: "%" (expected "tiny", "short" or "long")', p_size;
                result := 'f';
            END IF;

            RETURN result;
        END;
        \$\$ LANGUAGE plpgsql;

END
      ;

    return $sql;
}

# get the sql function definitions
sub get_sql_function_definitions
{
    my $sql = '';

    # append is_stop_stem()
    $sql .= get_is_stop_stem_function_tables_and_definition();

    return $sql;
}

# add all of the functions defined in $_functions to the database
sub add_functions
{
    my ( $db ) = @_;

    eval { $db->query( 'create language plperlu' ); };

    my $sql = get_sql_function_definitions();
    $db->query( $sql );
}

# removes all relations belonging to a given schema
# default schema is 'public'
sub reset_schema($;$)
{
    my ( $db, $schema ) = @_;

    $schema ||= 'public';

    # TODO: should check for failure
    {
        my $old_handler = $SIG{ __WARN__ };

        $SIG{ __WARN__ } = 'IGNORE';

        #sub {
        # say 'ignoring warning';
        #};

        no warnings;

        # By default this will complain but the drop cascading to other objects
        # THis warning is just noise so get rid of it.

        $db->dbh->trace( 0 );
        say STDERR Dumper( $db->dbh->trace );

        $db->query( "DROP SCHEMA IF EXISTS $schema CASCADE" );

        my $postgres_version = $db->query( 'SELECT VERSION() AS version' )->hash;
        $postgres_version = $postgres_version->{ version };
        $postgres_version =~ s/^\s+//;
        $postgres_version =~ s/\s+$//;

        unless ( $postgres_version =~ /^PostgreSQL 8/ )
        {

            # Assume PostgreSQL 9+ ('DROP EXTENSION' is only available+required since that version)
            $db->query( "DROP EXTENSION IF EXISTS plpgsql CASCADE" );
        }
        $db->query( "DROP LANGUAGE IF EXISTS plpgsql CASCADE" );

        $SIG{ __WARN__ } = $old_handler;
    }

    $db->query( "CREATE LANGUAGE plpgsql" );

    # these schemas will be created later so don't recreate it here
    if ( ( $schema ne 'enum' ) && ( $schema ne 'cd' ) )
    {
        $db->query( "CREATE SCHEMA $schema" );
    }

    return undef;
}

# recreates all schemas
sub reset_all_schemas($)
{
    my ( $db ) = @_;

    reset_schema( $db, 'public' );

    # removes schema used by dklab enum procedures
    # schema will be re-added in dklab sqlfile
    reset_schema( $db, 'enum' );

    # schema to hold all of the controversy dump snapshot tables
    reset_schema( $db, 'cd' );

    reset_schema( $db, 'stories_tags_map_media_sub_tables' );
}

# loads and runs a given SQL file
# useful for rebuilding the database schema after a call to reset_schema
sub load_sql_file
{
    my ( $label, $sql_file ) = @_;

    sub parse_line
    {
        my ( $line ) = @_;

        chomp( $line );

        #say "Got line: '$line'";

        # Die on unexpected SQL (e.g. DROP TABLE)
        if (
            not $line =~
/^NOTICE:|^CREATE|^ALTER|^\SET|^COMMENT|^INSERT|^ enum_add.*|^----------.*|^\s+|^\(\d+ rows?\)|^$|^DROP LANGUAGE|^DROP VIEW|^DROP TABLE|^drop cascades to view |^UPDATE \d+|^DROP TRIGGER|^Timing is on\.|^DROP INDEX|^psql.*: NOTICE:/
          )
        {

            # Make an exception for the fancy way of creating Pg languages
            if ( not $line =~ /^DROP FUNCTION/ )
            {
                carp "Evil line: '$line'";
                die "Evil line: '$line'";
            }
        }

        return "$line\n";
    }

    my $db_settings = MediaWords::DB::connect_settings( $label );
    my $script_dir  = MediaWords::Util::Config::get_config()->{ mediawords }->{ script_dir };
    my $db_type     = $db_settings->{ type };
    my $host        = $db_settings->{ host };
    my $database    = $db_settings->{ db };
    my $username    = $db_settings->{ user };
    my $port        = $db_settings->{ port };
    my $password    = $db_settings->{ pass } . "\n";

    say "$host $database $username $password ";

    # TODO: potentially brittle, $? should be checked after run3
    # common shell script interface gives indirection to database with no
    # modification of this code.
    # if there is a way to do this without popping out to a shell, please use it

    # stdout and stderr go to this script's channels. password is passed on stdin
    # so it doesn't appear in the process table
    say STDERR "loadsql: $script_dir/loadsql.$db_type.sh";
    run3( [ "$script_dir/loadsql.$db_type.sh", $sql_file, $host, $database, $username, $port ],
        \$password, \&parse_line, \&parse_line );

    my $ret = $?;
    return $ret;
}

sub recreate_db
{
    my ( $label ) = @_;

    {
        my $do_not_check_schema_version = 1;
        my $db = MediaWords::DB::connect_to_db( $label, $do_not_check_schema_version );

        say STDERR "reset schema ...";

        reset_all_schemas( $db );
        say STDERR "add functions ...";
        MediaWords::Pg::Schema::add_functions( $db );
        say STDERR "add functions completed ...";

        $db->disconnect;
    }

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;

    say STDERR "script_dir: $script_dir";

    say STDERR "add enum functions ...";
    my $load_dklab_postgresql_enum_result = load_sql_file( $label, "$script_dir/dklab_postgresql_enum_2009-02-26.sql" );

    die "Error adding dklab_postgresql_enum procecures" if ( $load_dklab_postgresql_enum_result );

    say STDERR "add mediacloud schema ...";
    my $load_sql_file_result = load_sql_file( $label, "$script_dir/mediawords.sql" );

    return $load_sql_file_result;
}

# Upgrade database schema to the latest version
# (returns 1 on success, 0 on failure)
sub upgrade_db($;$)
{
    my ( $label, $echo_instead_of_executing ) = @_;

    my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir } || $FindBin::Bin;
    say STDERR "script_dir: $script_dir";
    my $db;
    {

        my $do_not_check_schema_version = 1;
        $db = MediaWords::DB::connect_to_db( $label, $do_not_check_schema_version );
    }

    # Current schema version
    my $schema_version_query =
      "SELECT value AS schema_version FROM database_variables WHERE name = 'database-schema-version' LIMIT 1";
    my @schema_versions        = $db->query( $schema_version_query )->flat();
    my $current_schema_version = $schema_versions[ 0 ] + 0;
    unless ( $current_schema_version )
    {
        say STDERR "Invalid current schema version.";
        return 0;
    }
    say STDERR "Current schema version: $current_schema_version";

    # Target schema version
    open SQLFILE, "$script_dir/mediawords.sql" or die $!;
    my @sql = <SQLFILE>;
    close SQLFILE;
    my $target_schema_version = MediaWords::Util::SchemaVersion::schema_version_from_lines( @sql );
    unless ( $target_schema_version )
    {
        say STDERR "Invalid target schema version.";
        return 0;
    }

    say STDERR "Target schema version: $target_schema_version";

    if ( $current_schema_version == $target_schema_version )
    {
        say STDERR "Schema is up-to-date, nothing to upgrade.";
        return 1;
    }
    if ( $current_schema_version > $target_schema_version )
    {
        say STDERR "Current schema version is newer than the target schema version, please update the source code.";
        return 0;
    }

    # Check if the SQL diff files that are needed for upgrade are present before doing anything else
    my @sql_diff_files;
    for ( my $version = $current_schema_version ; $version < $target_schema_version ; ++$version )
    {
        my $diff_filename = './sql_migrations/mediawords-' . $version . '-' . ( $version + 1 ) . '.sql';
        unless ( -e $diff_filename )
        {
            say STDERR "SQL diff file '$diff_filename' does not exist.";
            return 0;
        }

        push( @sql_diff_files, $diff_filename );
    }

    # Import diff files one-by-one
    foreach my $diff_filename ( @sql_diff_files )
    {
        if ( $echo_instead_of_executing )
        {
            say STDERR "Echoing out $diff_filename to STDOUT...";

            print "-- --------------------------------\n";
            print "-- This is a concatenated schema diff between versions " .
              "$current_schema_version and $target_schema_version.\n";
            print "-- Please review this schema diff and import it manually.\n";
            print "-- --------------------------------\n\n\n";

            open DIFF, "< $diff_filename" or die "Can't open $diff_filename : $!\n";
            while ( <DIFF> )
            {
                print;
            }
            close DIFF;

            print "\n-- --------------------------------\n\n\n";

        }
        else
        {
            say STDERR "Importing $diff_filename...";

            my $load_sql_file_result = load_sql_file( $label, $diff_filename );
            if ( $load_sql_file_result )
            {
                say STDERR "Executing SQL diff file '$diff_filename' failed.";
                return 1;
            }
        }

    }

    if ( !$echo_instead_of_executing )
    {
        say STDERR "(Re-)adding functions...";
        MediaWords::Pg::Schema::add_functions( $db );
    }

    $db->disconnect;

    say STDERR "Done.";

    return 1;
}

1;
