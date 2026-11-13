/// The one switch for everything Fuliza that the user can see (the page, the Home lines, the "How it was
/// paid" block, the Settings row, the Fuliza count on Delete data). Off in 0.2.0: mmogo still reads and
/// keeps the Fuliza messages on the phone, but shows nothing from them. Turn it on to bring the screens back.
/// A variable rather than a const only so tests of the dormant screens can switch it on.
bool fulizaVisible = false;
