const { performance } = require('perf_hooks');

const iterations = 10_000_000;

function benchStringConversion() {
    let start = performance.now();
    let sum = 0;
    for (let i = 0; i < iterations; i++) {
        let newUIVal = 1.23456 + (i % 100) * 0.01;
        newUIVal = parseFloat(newUIVal.toFixed(2));
        let strVal = newUIVal.toString();
        let parsed = parseFloat(strVal);
        sum += parsed;
    }
    let end = performance.now();
    console.log(`String conversion: ${end - start} ms`);
}

function benchMathRound() {
    let start = performance.now();
    let sum = 0;
    for (let i = 0; i < iterations; i++) {
        let newUIVal = 1.23456 + (i % 100) * 0.01;
        newUIVal = Math.round(newUIVal * 100) / 100;
        let parsed = newUIVal; // simulating no toString() -> parseFloat()
        sum += parsed;
    }
    let end = performance.now();
    console.log(`Math.round: ${end - start} ms`);
}

benchStringConversion();
benchMathRound();
