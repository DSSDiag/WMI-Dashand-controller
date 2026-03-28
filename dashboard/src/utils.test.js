import { describe, it, expect } from 'vitest';
import { formatBoost } from './utils';

describe('formatBoost', () => {
  it('formats PSI correctly (gauge)', () => {
    expect(formatBoost(10, 'psi', 'gauge')).toBe('10.0');
    expect(formatBoost(-5, 'psi', 'gauge')).toBe('-5.0');
    expect(formatBoost(0, 'psi', 'gauge')).toBe('0.0');
  });

  it('formats PSI correctly (absolute)', () => {
    // ATM_PSI is 14.7
    expect(formatBoost(10, 'psi', 'abs')).toBe('24.7');
    expect(formatBoost(-5, 'psi', 'abs')).toBe('9.7');
    expect(formatBoost(0, 'psi', 'abs')).toBe('14.7');
  });

  it('formats BAR correctly (gauge)', () => {
    // 10 psi * 0.0689476 = 0.689476 => '0.69'
    expect(formatBoost(10, 'bar', 'gauge')).toBe('0.69');
    expect(formatBoost(-5, 'bar', 'gauge')).toBe('-0.34');
    expect(formatBoost(0, 'bar', 'gauge')).toBe('0.00');
  });

  it('formats BAR correctly (absolute)', () => {
    // 24.7 psi * 0.0689476 = 1.7030 => '1.70'
    expect(formatBoost(10, 'bar', 'abs')).toBe('1.70');
    // 9.7 psi * 0.0689476 = 0.66879 => '0.67'
    expect(formatBoost(-5, 'bar', 'abs')).toBe('0.67');
  });

  it('formats KPA correctly (gauge)', () => {
    // 10 psi * 6.89476 = 68.9476 => '68.9'
    expect(formatBoost(10, 'kpa', 'gauge')).toBe('68.9');
    expect(formatBoost(-5, 'kpa', 'gauge')).toBe('-34.5');
    expect(formatBoost(0, 'kpa', 'gauge')).toBe('0.0');
  });

  it('formats KPA correctly (absolute)', () => {
    // 24.7 psi * 6.89476 = 170.30 => '170.3'
    expect(formatBoost(10, 'kpa', 'abs')).toBe('170.3');
    // 9.7 psi * 6.89476 = 66.879 => '66.9'
    expect(formatBoost(-5, 'kpa', 'abs')).toBe('66.9');
  });

  it('formats PSI/inHg correctly (gauge)', () => {
    // > -0.1 displays as PSI
    expect(formatBoost(10, 'psi_inhg', 'gauge')).toBe('10.0 PSI');
    expect(formatBoost(-0.05, 'psi_inhg', 'gauge')).toBe('-0.1 PSI');
    expect(formatBoost(0, 'psi_inhg', 'gauge')).toBe('0.0 PSI');

    // <= -0.1 displays as inHg
    // -0.1 psi * -2.03602 = 0.2036 => '0 inHg'
    expect(formatBoost(-0.1, 'psi_inhg', 'gauge')).toBe('0 inHg');
    // -5 psi * -2.03602 = 10.18 => '10 inHg'
    expect(formatBoost(-5, 'psi_inhg', 'gauge')).toBe('10 inHg');
    // -14.73 psi * -2.03602 = 29.99 => '30 inHg'
    expect(formatBoost(-14.73, 'psi_inhg', 'gauge')).toBe('30 inHg');
  });

  it('formats PSI/inHg correctly (absolute)', () => {
    // pressureRef 'abs' is ignored for 'psi_inhg' in the current implementation
    // The code says: const isAbs = pressureRef === 'abs' && units !== 'psi_inhg';
    expect(formatBoost(10, 'psi_inhg', 'abs')).toBe('10.0 PSI');
    expect(formatBoost(-5, 'psi_inhg', 'abs')).toBe('10 inHg');
  });
});
