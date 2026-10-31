Desktop tests for the native deck engine (pure Java, no Android needed):

    E=android/app/src/main/java/com/baz/djmusi/engine
    javac -d /tmp/et $E/DeckEngine.java $E/Biquad.java $E/BeatDetector.java $E/SamplerEngine.java $E/Mixer.java tool/engine_test/*.java
    java -cp /tmp/et EngineTest    # playback, scratching, loops, tempo
    java -cp /tmp/et EngineTest2   # EQ, filter, FX and BPM detection
    java -cp /tmp/et EngineTest3   # sampler pads, headphone split cue, waveform colors
