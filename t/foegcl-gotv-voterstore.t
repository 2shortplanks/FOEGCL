use Modern::Perl;

{
    package Test::FOEGCL::GOTV::VoterStore;
    
    BEGIN { chdir 't' if -d 't' }
    use lib '../lib', 'lib';
    use Moo;
    extends 'FOEGCLModuleTestTemplate';
    use MooX::Types::MooseLike::Base qw( :all );
    use Test::More;
    use Test::Exception;
    use English qw( -no_match_vars );
    use Readonly;

    Readonly my $TEST_VOTER_DATAFILE => 'voterprovider-test-datafile.csv';

    has _friends => ( is => 'ro', isa => ArrayRef[ InstanceOf[ 'FOEGCL::GOTV::Friend' ] ], builder => 1, lazy => 1);
    has _voter_store => ( is => 'rw', isa => InstanceOf[ 'FOEGCL::GOTV::VoterStore' ] );

    around _build__module_under_test => sub {
        return 'FOEGCL::GOTV::VoterStore';
    };
    
    sub _build__friends {
        my $self = shift;
        
        return [
            map {
                FOEGCL::GOTV::Friend->new( %$_ )
            } ($self->_read_data_csv( $self->_friend_attrs ))
        ];
    }
    
    after _check_prereqs => sub {
        my $self = shift;

        # Skip these tests if FOEGCL::GOTV::Friend doesn't work
        plan(skip_all => "requires FOEGCL::GOTV::Friend to work") if        
            ! eval 'use FOEGCL::GOTV::Friend; 1';
    };
    
    around _test_instantiation => sub {
        my $orig = shift;
        my $self = shift;
        
        $self->_voter_store( $self->$orig );
    };
    
    around _test_methods => sub {
        my $orig = shift;
        my $self = shift;
        
        subtest $self->_module_under_test . '->add_voter' => sub {
            $self->_test_method_add_voter
        };
        
        subtest $self->_module_under_test . '->any_friends_match_direct' => sub {
            $self->_test_method_any_friends_match_direct
        };

        subtest $self->_module_under_test . '->has_voter_like_friend' => sub {
            $self->_test_method_has_voter_like_friend
        };
        
        subtest $self->_module_under_test . '->any_friends_match_assisted' => sub {
            $self->_test_method_any_friends_match_assisted
        };
    };
    
    sub _test_method_add_voter {
        my $self = shift;
        
        can_ok($self->_voter_store, 'add_voter');
        plan(skip_all => $self->_module_under_test . " can't add_voter!") if
            ! $self->_voter_store->can('add_voter');
        plan(skip_all => "test requires FOEGCL::GOTV::VoterProvider") if
            ! eval 'use FOEGCL::GOTV::VoterProvider; 1';

        my $voter_provider = FOEGCL::GOTV::VoterProvider->new(
            datafile => $TEST_VOTER_DATAFILE
        );
        
        lives_ok {
            while (my $voter = $voter_provider->next_record) {
                $self->_voter_store->add_voter($voter);            
            }
        } 'add voters';
    }
    
    sub _test_method_any_friends_match_direct {
        my $self = shift;
        
        can_ok($self->_voter_store, 'any_friends_match_direct');
        plan(skip_all => $self->_module_under_test . " can't any_friends_match_direct!") if
            ! $self->_voter_store->can('any_friends_match_direct');
        plan(skip_all => "voter store has no items in it") if
            scalar keys %{ $self->_voter_store->_item_store } == 0;
        
        # Test a group of three friends which do not have a direct match
        ok(
            ! $self->_voter_store->any_friends_match_direct(
                @{ $self->_friends }[1,2,3]
            ),
            "don't find known non-voters"
        );
        
        # Test a group of three friends of which one has a direct match
        ok(
            $self->_voter_store->any_friends_match_direct(
                @{ $self->_friends }[2,3,4]
            ),
            "find known voter in a group of otherwise non-voters"
        );        
        
        # Test a group of three friends of which all have a direct match
        ok(
            $self->_voter_store->any_friends_match_direct(
                @{ $self->_friends }[4,5,6]
            ),
            "find known voter in a group of them"
        );    
    }
    
    sub _test_method_has_voter_like_friend {
        my $self = shift;

        can_ok($self->_voter_store, 'has_voter_like_friend');
        plan(skip_all => $self->_module_under_test . " can't has_voter_like_friend!") if
            ! $self->_voter_store->can('has_voter_like_friend');
        plan(skip_all => "voter store has no items in it") if
            scalar keys %{ $self->_voter_store->_item_store } == 0;
        
        # Test that we succeed in finding a voter like a friend
        ok(
            $self->_voter_store->has_voter_like_friend(
                $self->_friends->[0]
            ),
            'find known voter'
        );
        
        # Test that we fail in finding a voter like a friend that's not there
        ok(
            ! $self->_voter_store->has_voter_like_friend(
                $self->_friends->[1]
            ),
            "don't find known non-voter"
        );
    }
    
    sub _test_method_any_friends_match_assisted {
        my $self = shift;
        
        can_ok($self->_voter_store, 'any_friends_match_assisted');
        plan(skip_all => $self->_module_under_test . " can't any_friends_match_assisted!") if
            ! $self->_voter_store->can('any_friends_match_assisted');
        plan(skip_all => "voter store has no items in it") if
            scalar keys %{ $self->_voter_store->_item_store } == 0;

        # Simulate user-entered prompt and response
        my $user_input =
            $INPUT_RECORD_SEPARATOR.           # User selects no match
            '17' . $INPUT_RECORD_SEPARATOR .    # User enters invalid value
            '1' . $INPUT_RECORD_SEPARATOR;      # User enters valid value
            
        open(my $old_stdin, '<&', \*STDIN) or die "Can't dup STDIN: $OS_ERROR";
        close STDIN or die "Can't close STDIN: $OS_ERROR";
        open(STDIN, '<', \$user_input) or die "Can't reopen STDIN: $OS_ERROR";
        
        # Test that when a user enters nothing, it fails
        ok(
            ! $self->_test_case_quiet_friends_match_assisted(
                $self->_friends->[5]
            ),
            'find no match when user selects no match'
        );
        
        # Test that when a user selects a valid voter, it succeeds
        ok(
            $self->_test_case_quiet_friends_match_assisted(
                $self->_friends->[5]
            ),
            'find a match when user selects a match'
        );
        
        # Reset STDIN
        close STDIN or die "Can't close scalar-based STDIN: $OS_ERROR";
        open(STDIN, '<&', $old_stdin) or die "Can't replace STDIN: $OS_ERROR";
    }
    
    # Temporarily eat STDOUT for clean testing
    sub _test_case_quiet_friends_match_assisted {
        my $self = shift;
        my @friends = @_;
        
        my $program_output = '';
        open(my $old_stdout, '>&', \*STDOUT) or die "Can't dup STDOUT: $OS_ERROR";
        close STDOUT or die "Can't close STDOUT: $OS_ERROR";
        open(STDOUT, '>', \$program_output) or die "Can't reopen STDOUT: $OS_ERROR";
        select STDOUT; $OUTPUT_AUTOFLUSH = 1;
        
        my $rv = $self->_voter_store->any_friends_match_assisted(@friends);
        
        close STDOUT or die "Can't close scalar-based STDOUT: $OS_ERROR";
        open(STDOUT, '>&', $old_stdout) or die "Can't replace STDOUT: $OS_ERROR";
        
        $program_output =~ s/$INPUT_RECORD_SEPARATOR/$INPUT_RECORD_SEPARATOR\t\t- /g;
        print "\t\t- $program_output\n";
        
        return $rv;
    }
    
    sub _friend_attrs {
        return qw( friend_id first_name last_name street_address zip registered_voter );
    }
}

Test::FOEGCL::GOTV::VoterStore->new->run;

# friend_id, first_name, last_name, street_address, zip, registered_voter
__DATA__
1461009011,Pamela,Harris,7343 Annamark 780,12144,1
1461009012,Pamela,Harris,7343 Placebo St.,12144,0
82418104,Jim,Stevens,8 Gramelda Ln.,12061,0
196920294,Anne,Murray,43 West Stoffels Lane,12033,0
2165671540,Jack,Hunt,534 Fordem,12144,1
1391004024,Irene,Rogers,1388 Thierer,12144,1
1052372292,Eugene,Scott,1486 Starling 989,12144,1