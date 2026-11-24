import Foundation
func check(_ condition: @autoclosure ()->Bool,_ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n",stderr); exit(1) }
}
let ids = EffectRegistry.all.map(\.id)
check(Set(ids).count == ids.count,"Duplicate stable effect IDs")
check(Set(EffectRegistry.all.map(\.gpuMode)).count == ids.count,"Duplicate GPU modes")
for definition in EffectRegistry.all {
    check(Set(definition.parameters.map(\.key)).count == definition.parameters.count,"Duplicate parameter keys")
}
var settings = SignalSettings(); settings.activeEffect = .displace
settings.set("amplitude",42); settings.seed = UInt32.max; settings.intensity = 0.83
settings.activeEffect = .solar; settings.set("low",0.7); settings.set("curve",1); settings.intensity = 0.2
settings.activeEffect = .displace
check(settings.value("amplitude") == 42 && settings.seed == UInt32.max && settings.intensity == 0.83,"Effect state leaked across selections")
settings.activeEffect = .solar
check(settings.value("low") == 0.7 && settings.value("curve") == 1 && settings.intensity == 0.2,"Solar state was lost")
settings.set("low",1); check(settings.value("high") >= settings.value("low")+0.00499,"Solar lower threshold crossed upper")
settings.set("high",0); check(settings.value("low") <= settings.value("high")-0.00499,"Solar upper threshold crossed lower")
settings.set("curve",99); check(settings.value("curve") == 2,"Enum range not clamped")
settings.set("low",.nan); check(settings.value("low").isFinite,"NaN reached shader parameter")
settings.exposure = .infinity; settings.gamma = -.infinity; settings.contrast = -100
settings = settings.normalized()
check(settings.exposure == 0 && settings.gamma == 1 && settings.contrast == 0.5,"Global validation failed")
settings.saturation = 0.3
let effectsBeforeReset = settings.perEffect
settings.resetColor(); check(settings.perEffect == effectsBeforeReset && settings.saturation == 1,"Color reset damaged effects")
settings.saturation = 0.3; settings.resetEffect()
check(settings.saturation == 0.3 && settings.value("low") == 0.35,"Effect reset damaged global color")
settings.activeEffect = .displace
check(settings.value("amplitude") == 42 && settings.seed == UInt32.max,"Reset changed inactive effect")
let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
let url = folder.appendingPathComponent("settings.json")
defer { try? FileManager.default.removeItem(at: folder) }
let store = SettingsStore(url: url)
try store.save(settings)
let restored = try store.load()
check(restored == settings.normalized(),"Settings JSON did not round trip")
check(restored.seed == UInt32.max,"32-bit seed precision was lost")
let future = Data("{\"schemaVersion\":99,\"settings\":{}}".utf8)
try future.write(to: url)
let futureStore = SettingsStore(url: url)
do { _ = try futureStore.load(); check(false,"Future schema was accepted") } catch {}
do { try futureStore.save(settings); check(false,"Future schema was overwritten") } catch {}
let futureAfter = try Data(contentsOf: url)
check(futureAfter == future,"Future schema file changed")
let corrupt = Data("not JSON".utf8); try corrupt.write(to: url)
let corruptStore = SettingsStore(url: url)
do { _ = try corruptStore.load(); check(false,"Corrupt settings accepted") } catch {}
do { try corruptStore.save(settings); check(false,"Corrupt settings overwritten") } catch {}
let corruptAfter = try Data(contentsOf: url)
check(corruptAfter == corrupt,"Corrupt file changed")
var clock = FrameClock()
_ = clock.advance(3599.98)
let next = clock.advance(3600.02)
check(abs(next.delta-0.04) < 0.0001 && !next.discontinuity,"Hour boundary broke source clock")
let gap = clock.advance(3601)
check(gap.discontinuity,"Large PTS gap not detected")
check(clock.advance(3600).discontinuity,"Nonmonotonic PTS not detected")
let presetURL = folder.appendingPathComponent("presets.json")
let presets = PresetStore(url: presetURL)
try presets.load()
var look = SignalSettings(); look.activeEffect = .edge; look.set("threshold",0.42); look.saturation = 0.35
let saved = try presets.saveNew(name: "  My   Look  ",settings: look)
check(saved.name == "My Look","Preset name whitespace not normalized")
check(saved.settings.perEffect.count == 1,"Preset unnecessarily captured inactive effect values")
do { _ = try presets.saveNew(name: "my look",settings: look); check(false,"Duplicate name accepted") } catch {}
do { _ = try presets.saveNew(name: "   ",settings: look); check(false,"Empty name accepted") } catch {}
let reloaded = PresetStore(url: presetURL); try reloaded.load()
check(reloaded.presets.count == 1 && reloaded.presets[0].id == saved.id,"Saved preset did not survive reload")
var unrelated = SignalSettings(); unrelated.activeEffect = .displace; unrelated.set("amplitude",55)
let applied = reloaded.presets[0].applying(to: unrelated)
check(applied.activeEffect == .edge && applied.value("threshold") == 0.42 && applied.saturation == 0.35,"Preset did not restore active tuning and color")
var back = applied; back.activeEffect = .displace
check(back.value("amplitude") == 55,"Preset recall erased unrelated effect tuning")
look.set("threshold",0.6); try reloaded.update(saved.id,settings: look)
try reloaded.rename(saved.id,to: "Ink Look")
check(reloaded.presets[0].id == saved.id && reloaded.presets[0].name == "Ink Look","Rename replaced identity")
try reloaded.delete(saved.id); check(reloaded.presets.isEmpty,"Delete did not hide preset")
let restoredStore = PresetStore(url: presetURL); try restoredStore.load(); try restoredStore.restore(saved.id)
check(restoredStore.presets[0].settings.value("threshold") == 0.6,"Recoverable delete lost updated tuning")
let blocked = folder.appendingPathComponent("blocked")
try Data("file".utf8).write(to: blocked)
let failingStore = PresetStore(url: blocked.appendingPathComponent("presets.json"))
do { _ = try failingStore.saveNew(name: "Cannot Write",settings: look); check(false,"Failed write accepted") } catch {}
check(failingStore.presets.isEmpty,"Failed write mutated live preset list")
try Data("{\"schemaVersion\":99,\"presets\":[]}".utf8).write(to: presetURL)
let protectedStore = PresetStore(url: presetURL)
do { try protectedStore.load(); check(false,"Future preset schema accepted") } catch {}
do { _ = try protectedStore.saveNew(name: "No Overwrite",settings: look); check(false,"Protected preset file overwritten") } catch {}
let coverage = HalftoneCoverage.table()
check(zip(coverage,coverage.dropFirst()).allSatisfy { $0 <= $1 },"Halftone radius LUT is not monotonic")
for (index,radius) in coverage.enumerated() {
    check(abs(HalftoneCoverage.area(radius: Double(radius))-Double(index)/255) < 0.00001,"Halftone coverage does not match requested tone")
}
var matrixLook = SignalSettings(); matrixLook.activeEffect = .matrix
matrixLook.set("ink",10); matrixLook.set("hue",275); matrixLook.set("fade",1.3); matrixLook.set("ghost",0.82)
let tintStore = PresetStore(url: folder.appendingPathComponent("matrix-presets.json"))
let tintPreset = try tintStore.saveNew(name: "Violet Ghost",settings: matrixLook)
let recalledTint = tintPreset.applying(to: SignalSettings())
check(recalledTint.value("ink") == 10 && recalledTint.value("hue") == 275 && recalledTint.value("fade") == 1.3 && recalledTint.value("ghost") == 0.82,"Preset lost custom hue or ghost fade")
check(EffectRegistry.definition(.matrix).parameters.first(where: { $0.key == "ink" })!.validated(2) == 2,"Existing source-color ink ID changed")
print("PASS: registry, tuning isolation, settings, source clock, named preset CRUD/recall/undo, failed-write protection and halftone coverage")

// Every added effect must survive settings and named-look serialization with isolated tuning.
for definition in EffectRegistry.advanced {
    var look=SignalSettings(); look.activeEffect=definition.id; look.intensity=0.91
    for parameter in definition.parameters {
        look.set(parameter.key,parameter.range.upperBound)
        check(look.value(parameter.key).isFinite,"Nonfinite advanced parameter")
    }
    let roundTrip=try JSONDecoder().decode(SignalSettings.self,from: JSONEncoder().encode(look))
    check(roundTrip.normalized()==look.normalized(),"Advanced effect settings did not round-trip")
    let saved=try tintStore.saveNew(name: definition.title,settings: look)
    let recalled=saved.applying(to: SignalSettings())
    check(recalled.activeEffect==definition.id && recalled.current==look.normalized().current,"Advanced named preset lost effect tuning")
}
check(EffectRegistry.advanced.count==15,"Remaining effect inventory is incomplete")
print("PASS: all 15 added effects persist their tuning and named looks")

for definition in EffectRegistry.all {
    check(definition.parameters.count<=16,"Effect parameters exceed GPU uniform capacity")
}
var recipes=SignalSettings(); recipes.activeEffect = .block
recipes.set("preset",1); check(recipes.value("levels")==2,"Crushed recipe did not update residual-level slider")
recipes.set("levels",17)
check(recipes.normalized().value("levels")==17,"Normalization overwrote custom residual levels with recipe defaults")
let recipeSaved=try tintStore.saveNew(name: "Custom residual recipe",settings: recipes)
check(recipeSaved.applying(to: SignalSettings()).value("levels")==17,"Named recipe lost manual residual adjustment")
recipes.set("preset",4); check(recipes.value("levels")==12,"Residual heat recipe did not update levels")
var asciiPaper=SignalSettings(); asciiPaper.activeEffect = .ascii; asciiPaper.set("invert",2)
check(asciiPaper.value("invert")==2,"Dark-paper polarity is unavailable")
check(EffectRegistry.definition(.fluid).parameters.allSatisfy { $0.key != "hue" && $0.key != "color" },"Fluid feedback tint controls were retained")
print("PASS: recipe slider coupling, manual override persistence, dark paper and 16-parameter GPU contract")

// Fill must cover every target edge without changing aspect ratio; fit must contain the image.
for target in [CGSize(width: 800,height: 800),CGSize(width: 1600,height: 400),CGSize(width: 400,height: 1200),CGSize(width: 1920,height: 1080)] {
    let source=CGSize(width: 1920,height: 1080)
    let filled=PreviewLayout.placement(source: source,target: target,fill: true)!
    check(filled.minX<=0.001 && filled.minY<=0.001 && filled.maxX>=target.width-0.001 && filled.maxY>=target.height-0.001,"Fill leaves a border")
    check(abs(filled.width/filled.height-16.0/9.0)<0.00001,"Fill distorts the camera")
    check(abs(filled.midX-target.width/2)<0.001 && abs(filled.midY-target.height/2)<0.001,"Fill crop is not centered")
    let fitted=PreviewLayout.placement(source: source,target: target,fill: false)!
    check(fitted.minX>=(-0.001) && fitted.minY>=(-0.001) && fitted.maxX<=target.width+0.001 && fitted.maxY<=target.height+0.001,"Fit crops the camera")
}
check(PreviewLayout.placement(source: .zero,target: CGSize(width: 800,height: 600),fill: true)==nil,"Zero source accepted")
check(PreviewLayout.placement(source: CGSize(width: 1920,height: 1080),target: .zero,fill: true)==nil,"Zero drawable accepted")
print("PASS: preview fill/fit coverage, aspect ratio, centered crop and invalid dimensions")
