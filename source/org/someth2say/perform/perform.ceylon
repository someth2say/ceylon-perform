
import ceylon.random {
    DefaultRandom,
    randomize
}

import java.lang {
    Thread {
        javaSleep=sleep
    },
    System {
        javaGc=gc
    }
}

////////////////////////////

shared void run() {
    benchmark {
        iterations = 100k;
        scale = 1000;
        benchRounds = 20;
        "Basic Sum"->(() => (0:300).each((_) => 1 + 1)),
        "Object Sum"->(() => (0:300).each((_) => Integer(1) +Integer(2)))
    };
}

////////////////////////////

Integer nanosPerSecond = 1G;
Integer nanosPerMilli = 1M;

native
void gc() ;

//native("js", "dart")
//void gc() {}

native ("jvm")
void gc() => javaGc();

native
void sleep(Integer millis) ;

//native("js", "dart")
//void sleep(Integer millis) {}

native ("jvm")
void sleep(Integer millis)
        => javaSleep(millis);

"Returns the time (in nanoseconds) consumed to perform the test; and also, the result for the first test execution."
shared
[Integer, Result] time<Result>(Result() test, Integer iterations = 1) {
    "iterations must be at least 1"
    assert (iterations>=1);

    value start = system.nanoseconds;
    value result = test();
    for (i in 0:iterations - 1) {
        test();
    }
    value nanos = system.nanoseconds - start;
    return [nanos, result];
}

shared
void benchmark(
        tests, name=null, warmupRounds = 3, benchRounds = 5, scale = 1,
        sleepMillis = 100, iterations = 1, quiet = true,
        veryQuiet = false) {

    String? name;
    Integer warmupRounds;
    Integer benchRounds;
    Integer scale;
    Integer sleepMillis;
    Integer iterations;
    Boolean quiet;
    Boolean veryQuiet;
    {Anything()|<String->Anything()>+} tests;

    "iterations must be at least 1"
    assert (iterations>=1);

    Float nan = 0.0 / 0.0;

    Float lesser(Float x, Float y) => if (x != x || y<x) then y else x;

    Float greater(Float x, Float y) => if (x != x || y>x) then y else x;

    Integer roundInteger(Float x) => if (x.positive) then (x + 0.5).integer else (x - 0.5).integer;

    class RunningStats() {
        shared variable Integer sampleCount = 0;
        variable value runningMean = 0.0;
        variable value runningVariance = 0.0;

        variable Float runningMin = nan;
        variable Float runningMax = nan;

        // Knuth Volume 2 4.2.2 A15 and A16
        // Welford’s method
        shared
        void addSample(Float sample) {
            value prevMean = runningMean;
            runningMean += (sample - runningMean) /++sampleCount;             // m = x first iter
            runningVariance += (sample - runningMean) * (sample - prevMean);  // s = 0 first iter

            runningMin = lesser(runningMin, sample);
            runningMax = greater(runningMax, sample);
        }

        shared void reset() {
            sampleCount = 0;
            runningMean = 0.0;
            runningVariance = 0.0;

            runningMin = nan;
            runningMax = nan;
        }

        aliased ("minNanos")
        shared Float? minimum => sampleCount>0 then runningMin;

        aliased ("maxNanos")
        shared Float? maximum => sampleCount>0 then runningMax;

        aliased ("meanNanos")
        shared Float? mean => sampleCount>0 then runningMean;

        shared Float? variance => sampleCount>1 then runningVariance / (sampleCount - 1);

        shared Float? standardDeviation => variance?.power(0.5);

        shared Float? relativeStandardDeviation
                => if (exists standardDeviation = standardDeviation, exists mean = mean)
                then standardDeviation / mean * 100 else null;

    }

    Boolean? eq(Anything a, Anything b)
            => if (exists a, exists b) then a == b else if (a exists || b exists) then false else null;

    class TestResults<Result>(
            shared String name,
            shared Result() test,
            shared Integer scale,
            shared Integer iterations) {

        shared RunningStats stats = RunningStats();
        shared RunningStats totalStats = RunningStats();

        shared variable Result|Uninitialized firstExecResult = uninitialized;

        "Executes the test, as many times as defined in 'iterations', and update the stats.
         Finally, returns the total time used on executions."
        shared
        Float exec(Boolean warmup = false) {
            value [nanos, result] = time(test, iterations);

            value scaledNanos = nanos.float / scale / iterations;

// This should be optional, to check the results
//            if (!is Uninitialized firstExecResult = firstExecResult) {
//                if (!(eq(result, firstExecResult) else true)) {
//                    print("type of result = ``type(result)``");
//                    print("error, expected ``firstExecResult else "<null>"``, but got ``result else "<null>"``");
//                }
//            } else {
//                firstExecResult = result;
//            }

            if (!warmup) {
                stats.addSample(scaledNanos);
                totalStats.addSample(scaledNanos);
            }

            return scaledNanos;
        }

        shared void resetStats() => stats.reset();

    }

    value results = tests.indexed.collect((i->test) =>
    switch (test)
    case (is <String->Anything()>) TestResults(test.key, test.item, scale, iterations)
    else TestResults("Test #``i + 1``", test, scale, iterations));

    value random = DefaultRandom();

    value padding = max(results.map((t) => t.name.size)) + 1;

    function format(Float? float) => if (exists float) then Float.format(float,2,2) else "?";

    void printStats(Boolean total = false) {

        value sorted = results.sort((x, y) => ((total then x.totalStats else x.stats).minimum else 0.0) <=> ((total then y.totalStats else y.stats).minimum else 0.0));
        value best = (total then sorted.first.totalStats else sorted.first.stats).minimum;
        for (result in sorted) {
            value stats = total then result.totalStats else result.stats;
            value pct = if (exists best, exists min = stats.minimum)
            then Float.format(min * 100 / best, 0, 0) else "?";

            print(result.name.padTrailing(padding)
            + "``format(stats.minimum)``"
            + "/``format(stats.maximum)``"
            + "/``format(stats.mean)``"
            + (total then "/``format(stats.relativeStandardDeviation)``% " else " ")
            + "(``pct``%)");
        }
    }

    for (i in 1:warmupRounds) {
        if (!veryQuiet) {
            print("Warmup round ``i``/``warmupRounds``");
        }
        for (tr in randomize(results, random)) {
            sleep(sleepMillis);
            gc();
            value nanos = tr.exec(true);
            if (!veryQuiet&& !quiet) {
                print(tr.name.padTrailing(padding) + "``nanos.integer``\n");
            }
        }
    }

    for (i in 1:benchRounds) {
        if (!veryQuiet) {
            print("\nBenchmarking round ``i``/``benchRounds``");
        }

        for (tr in randomize(results, random)) {
            sleep(sleepMillis);
            gc();
            value nanos = tr.exec(false);
            value best = eq(nanos, tr.stats.minimum) else true;
            if (!veryQuiet&& !quiet) {
                print(tr.name.padTrailing(padding) + roundInteger(nanos).string + (if (best) then "*" else ""));
            }
        }
        if (!veryQuiet) {
            printStats();
        }

        results.collect((TestResults<Anything> element) => element.resetStats());
    }

    print("\n``name else "No-name"``: Summary min/max/avg/rstddev (pct): ``benchRounds`` rounds");
    printStats(true);

}

interface Uninitialized of uninitialized {}

object uninitialized satisfies Uninitialized {}