use base "y2logsstep";
use strict;
use testapi;

sub run(){
    my $self=shift;

    mouse_hide;
    assert_screen "second-stage", 250;

}

1;
