#!/usr/bin/env python3
"""Run the same XCTest source cases with Command Line Tools (no Xcode required)."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
build = root / '.build/core-tests'
build.mkdir(parents=True, exist_ok=True)
helpers = r'''
import Foundation
func failure(_ file: StaticString, _ line: UInt) -> Never { fatalError("Assertion failed", file: file, line: line) }
func XCTAssertTrue(_ a: @autoclosure () throws -> Bool, file: StaticString=#file, line: UInt=#line) { do { if try !a() { failure(file,line) } } catch { failure(file,line) } }
func XCTAssertFalse(_ a: @autoclosure () throws -> Bool, file: StaticString=#file, line: UInt=#line) { do { if try a() { failure(file,line) } } catch { failure(file,line) } }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString=#file, line: UInt=#line) { do { if try a() != b() { failure(file,line) } } catch { failure(file,line) } }
func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString=#file, line: UInt=#line) { do { if try a() <= b() { failure(file,line) } } catch { failure(file,line) } }
func XCTAssertNil<T>(_ a: @autoclosure () throws -> T?, file: StaticString=#file, line: UInt=#line) { do { if try a() != nil { failure(file,line) } } catch { failure(file,line) } }
func XCTAssertNotNil<T>(_ a: @autoclosure () throws -> T?, file: StaticString=#file, line: UInt=#line) { do { if try a() == nil { failure(file,line) } } catch { failure(file,line) } }
func XCTAssertThrowsError<T>(_ a: @autoclosure () throws -> T, _ handler: (Error)->Void = {_ in}, file: StaticString=#file, line: UInt=#line) { do { _ = try a(); failure(file,line) } catch { handler(error) } }
'''
sources, calls = [], []
for path in sorted((root/'Tests/OpenTypelessTests').glob('*.swift')):
    text = path.read_text().replace('import XCTest', '').replace('@testable import OpenTypelessCore', '').replace(': XCTestCase', '')
    name = re.search(r'final class (\w+)', text).group(1)
    sources.append(text)
    for method, throws in re.findall(r'func (test\w+)\(\)(\s+throws)?\s*\{', text):
        calls.append(('try ' if throws else '') + f'{name}().{method}(); print("PASS {method}")')
runner = build/'RunTests.swift'
runner.write_text(helpers+'\n'.join(sources)+'\n@main struct Runner { static func main() throws {\n'+'\n'.join(calls)+f'\nprint("Passed {len(calls)} tests")\n'+'}}\n')
subprocess.run(['swiftc','-module-cache-path',str(build/'modules'), *map(str, sorted((root/'Sources/OpenTypelessCore').glob('*.swift'))),str(runner),'-o',str(build/'tests')],check=True)
subprocess.run([str(build/'tests')],check=True)
