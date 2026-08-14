// ===========================================================================
// Bubble Pop! — Neon Ocean tap-bubble casual game
// Single-file Flutter + Flame game. No external assets, no extra libraries.
// ===========================================================================
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

// ===========================================================================
// Constants
// ===========================================================================

const String kGameTitle = 'BUBBLE POP';
const String kGameSubtitle = 'NEON OCEAN';
const String kFontFamily = 'SF Pro Display';

// Palette — soft neon ocean
const Color kColBgTop = Color(0xFF062B45);
const Color kColBgMid = Color(0xFF0A4D6E);
const Color kColBgBottom = Color(0xFF06243A);
const Color kColAccent = Color(0xFF34E0D0);
const Color kColAccent2 = Color(0xFF7C5CFF);
const Color kColGold = Color(0xFFFFD166);
const Color kColDanger = Color(0xFFFF4D6D);
const Color kColWhite = Color(0xFFF4FBFF);
const Color kColTextDim = Color(0xFF9BC4D6);

const double kBaseRiseSpeed = 90.0; // px/s @ level 1
const double kBaseSpawnInterval = 1.15; // s @ level 1
const int kStartLives = 3;
const int kLevelStepEvery = 600; // score per level

const List<List<Color>> kBubbleGradients = [
  [Color(0xFF34E0D0), Color(0xFF1B9DF0)],
  [Color(0xFFFF8FB1), Color(0xFFFF4D6D)],
  [Color(0xFFB388FF), Color(0xFF7C5CFF)],
  [Color(0xFFFFE066), Color(0xFFFF9F1C)],
  [Color(0xFF8AFF80), Color(0xFF19C37D)],
];

final Random _rng = Random();

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

// ===========================================================================
// Sound / Haptics stubs (interfaces only — no real implementation)
// ===========================================================================

void playSound([String? name]) {
  // Intentionally empty — audio interface reserved.
}

void vibrate() {
  // Intentionally empty — haptics interface reserved.
}

// ===========================================================================
// Score / Combo / Level / Difficulty logic
// ===========================================================================

class ScoreModel extends ChangeNotifier {
  ScoreModel();

  int _score = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _level = 1;
  int _lives = kStartLives;
  int _best = 0;

  int get score => _score;
  int get combo => _combo;
  int get maxCombo => _maxCombo;
  int get level => _level;
  int get lives => _lives;
  int get best => _best;

  int get multiplier => 1 + (_combo ~/ 5); // x1, x2, x3 ...

  void reset() {
    _score = 0;
    _combo = 0;
    _maxCombo = 0;
    _level = 1;
    _lives = kStartLives;
    notifyListeners();
  }

  void registerCollect(int basePoints) {
    _combo += 1;
    _maxCombo = max(_maxCombo, _combo);
    _score += basePoints * multiplier;
    _recomputeLevel();
    notifyListeners();
  }

  void registerMiss() {
    _combo = 0;
    _lives -= 1;
    notifyListeners();
  }

  void registerBombHit() {
    _combo = 0;
    _lives -= 1;
    notifyListeners();
  }

  void registerBombEscape() {
    // Bombs escaping is neutral — reward for dodging.
  }

  void breakComboGently() {
    if (_combo > 2) {
      _combo = _combo ~/ 2;
      notifyListeners();
    }
  }

  bool get isGameOver => _lives <= 0;

  void commitBest() {
    if (_score > _best) {
      _best = _score;
      notifyListeners();
    }
  }

  void _recomputeLevel() {
    final newLevel = 1 + (_score ~/ kLevelStepEvery);
    if (newLevel > _level) {
      _level = newLevel;
    }
  }
}

// Difficulty derived from level.
double riseSpeedFor(int level) => kBaseRiseSpeed + (level - 1) * 22.0;
double spawnIntervalFor(int level) =>
    _clamp(kBaseSpawnInterval - (level - 1) * 0.07, 0.42, kBaseSpawnInterval);
double bombChanceFor(int level) => _clamp(0.10 + (level - 1) * 0.015, 0.10, 0.30);
const double kBonusChance = 0.07;
double bubbleRadiusLow(int level) => _clamp(26.0 - (level - 1) * 0.6, 18.0, 26.0);
double bubbleRadiusHigh(int level) => _clamp(46.0 - (level - 1) * 0.4, 30.0, 46.0);

// ===========================================================================
// Enums
// ===========================================================================

enum GameState { ready, playing, paused, gameOver }

enum BubbleKind { normal, bonus, bomb }

extension BubbleKindX on BubbleKind {
  bool get isCollectible => this != BubbleKind.bomb;
}

// ===========================================================================
// Background Component
// ===========================================================================

class OceanBackground extends Component {
  OceanBackground()
    : _stars = List.generate(60, (_) => _Star()),
      _floaters = List.generate(8, (_) => _Floater());

  Vector2 _size = Vector2.zero();

  final List<_Star> _stars;
  final List<_Floater> _floaters;

  void resize(Vector2 s) => _size.setFrom(s);

  @override
  void render(Canvas canvas) {
    final w = _size.x;
    final h = _size.y;
    if (w <= 0 || h <= 0) return;

    // Vertical gradient
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(w / 2, 0),
        Offset(w / 2, h),
        [kColBgTop, kColBgMid, kColBgBottom],
        [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & Size(w, h), paint);

    // Soft radial glow at top
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w / 2, h * 0.12),
        w * 0.9,
        [kColAccent.withValues(alpha: 0.18), kColAccent.withValues(alpha: 0.0)],
        [0.0, 1.0],
      );
    canvas.drawRect(Offset.zero & Size(w, h), glow);

    // Stars
    for (final s in _stars) {
      final p = Paint()
        ..color = kColWhite.withValues(alpha: s.alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(s.x * w, s.y * h), s.radius, p);
    }

    // Floating translucent circles
    for (final f in _floaters) {
      final p = Paint()
        ..color = f.color.withValues(alpha: f.alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(f.x * w, f.y * h), f.radius, p);
    }

    // Vignette
    final vign = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w / 2, h / 2),
        max(w, h) * 0.75,
        [const Color(0x00000000), const Color(0x66000000)],
        [0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & Size(w, h), vign);
  }

  @override
  void update(double dt) {
    final h = _size.y;
    for (final s in _stars) {
      s.y -= s.speed * dt * 0.05;
      if (s.y < 0) s.y += 1.0;
      s.twinkle += dt * s.twinkleSpeed;
      s.alpha = 0.3 + 0.5 * (0.5 + 0.5 * sin(s.twinkle));
    }
    for (final f in _floaters) {
      f.y -= f.speed * dt * 0.02;
      if (f.y < -0.1) {
        f.y = 1.1;
        f.x = _rng.nextDouble();
      }
    }
    // h referenced to avoid unused-field lint; floaters use normalized coords.
    assert(h >= 0);
  }
}

class _Star {
  _Star()
    : x = _rng.nextDouble(),
      y = _rng.nextDouble(),
      radius = 0.5 + _rng.nextDouble() * 1.6,
      speed = 0.5 + _rng.nextDouble() * 1.5,
      alpha = 0.2 + _rng.nextDouble() * 0.6,
      twinkle = _rng.nextDouble() * pi * 2,
      twinkleSpeed = 1.0 + _rng.nextDouble() * 3.0;
  final double x;
  double y;
  final double radius;
  final double speed;
  double alpha;
  double twinkle;
  final double twinkleSpeed;
}

class _Floater {
  _Floater()
    : x = _rng.nextDouble(),
      y = _rng.nextDouble(),
      radius = 40 + _rng.nextDouble() * 90,
      speed = 0.4 + _rng.nextDouble() * 0.8,
      alpha = 0.03 + _rng.nextDouble() * 0.06,
      color = [kColAccent, kColAccent2, kColGold][_rng.nextInt(3)];
  double x;
  double y;
  final double radius;
  final double speed;
  final double alpha;
  final Color color;
}

// ===========================================================================
// Bubble Component
// ===========================================================================

class BubbleComponent extends CircleComponent with HasGameReference<BubblePopGame> {
  BubbleComponent({
    required this.kind,
    required double radius,
    required Vector2 position,
    required this.riseSpeed,
    required this.driftAmp,
    required this.driftFreq,
    required this.gradient,
  }) : _spawnX = position.x,
       _age = 0,
       super(radius: radius, position: position, anchor: Anchor.center);

  final BubbleKind kind;
  final double riseSpeed;
  final double driftAmp;
  final double driftFreq;
  final List<Color> gradient;
  final double _spawnX;
  double _age;

  late final Paint _fillPaint;
  late final Paint _glowPaint;
  late final Paint _ringPaint;
  late final Paint _highlightPaint;

  bool _popped = false;
  bool get isPopped => _popped;
  bool _counted = false;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final r = radius;

    _fillPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(-r * 0.3, -r * 0.3),
        r * 1.4,
        [gradient[0], gradient[1]],
        [0.0, 1.0],
      )
      ..style = PaintingStyle.fill;

    _glowPaint = Paint()
      ..color = gradient[0].withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    _ringPaint = Paint()
      ..color = kColWhite.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    _highlightPaint = Paint()
      ..color = kColWhite.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    // Spawn pop-in effect
    scale = Vector2.all(0.2);
    add(
      ScaleEffect.to(Vector2.all(1.0), EffectController(duration: 0.18, curve: Curves.easeOutBack)),
    );
  }

  @override
  void render(Canvas canvas) {
    final r = radius;
    canvas.drawCircle(Offset.zero, r * 1.05, _glowPaint);
    canvas.drawCircle(Offset.zero, r, _fillPaint);
    canvas.drawCircle(Offset.zero, r - 1, _ringPaint);
    canvas.drawCircle(Offset(-r * 0.32, -r * 0.36), r * 0.26, _highlightPaint);

    if (kind == BubbleKind.bomb) {
      final fuse = Paint()
        ..color = kColDanger
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawCircle(Offset.zero, r * 0.55, fuse);
      final x = r * 0.3;
      final xp = Paint()
        ..color = kColWhite
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(-x, -x), Offset(x, x), xp);
      canvas.drawLine(Offset(-x, x), Offset(x, -x), xp);
    } else if (kind == BubbleKind.bonus) {
      final star = Paint()
        ..color = kColWhite.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill;
      canvas.drawPath(_starPath(Offset.zero, r * 0.45, r * 0.2, 5), star);
    }
  }

  Path _starPath(Offset center, double outer, double inner, int points) {
    final path = Path();
    const startAngle = -pi / 2;
    for (int i = 0; i < points * 2; i++) {
      final rad = i.isEven ? outer : inner;
      final a = startAngle + i * pi / points;
      final x = center.dx + rad * cos(a);
      final y = center.dy + rad * sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  void update(double dt) {
    if (_popped) return;
    _age += dt;
    position.y -= riseSpeed * dt;
    position.x = _spawnX + sin(_age * driftFreq) * driftAmp;
    final w = 1.0 + 0.04 * sin(_age * 4.0);
    scale = Vector2.all(w);

    if (position.y + radius < 0) {
      _markEscaped();
    }
  }

  void _markEscaped() {
    if (_counted) return;
    _counted = true;
    if (kind.isCollectible) {
      game.onBubbleEscaped(this);
    } else {
      game.onBombEscaped(this);
    }
    if (parent != null) removeFromParent();
  }

  void pop() {
    if (_popped) return;
    _popped = true;
    _counted = true;
    game.spawnPopParticles(position, gradient[0], kind);

    add(ScaleEffect.to(Vector2.all(1.8), EffectController(duration: 0.12, curve: Curves.easeOut)));
    add(OpacityEffect.fadeOut(EffectController(duration: 0.12)));
    add(TimerComponent(period: 0.16, removeOnFinish: true, onTick: () => removeFromParent()));
  }
}

// ===========================================================================
// Particle helpers
// ===========================================================================

class ParticleBurst extends PositionComponent {
  ParticleBurst({
    required Vector2 position,
    required this.color,
    this.count = 14,
    this.speed = 180,
    this.life = 0.5,
    this.particleSize = 4.0,
  }) : super(position: position, anchor: Anchor.center);

  final Color color;
  final int count;
  final double speed;
  final double life;
  final double particleSize;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final particles = <Particle>[];
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * pi * 2 + _rng.nextDouble() * 0.3;
      final v = speed * (0.6 + _rng.nextDouble() * 0.6);
      particles.add(
        _DotParticle(
          position: Vector2.zero(),
          velocity: Vector2(cos(angle) * v, sin(angle) * v),
          color: color,
          lifespan: life * (0.7 + _rng.nextDouble() * 0.6),
          size: particleSize * (0.6 + _rng.nextDouble() * 0.8),
        ),
      );
    }
    add(ParticleSystemComponent(particle: ComposedParticle(children: particles)));
    add(TimerComponent(period: life + 0.2, removeOnFinish: true, onTick: () => removeFromParent()));
  }
}

class _DotParticle extends Particle {
  _DotParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required double lifespan,
    required this.size,
  }) : super(lifespan: lifespan);

  final Vector2 position;
  final Vector2 velocity;
  final Color color;
  final double size;

  @override
  void render(Canvas canvas) {
    final p = Paint()
      ..color = color.withValues(alpha: progress <= 1 ? (1 - progress) : 0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(position.x, position.y), size, p);
  }

  @override
  void update(double delta) {
    super.update(delta);
    position.x += velocity.x * delta;
    position.y += velocity.y * delta;
    velocity.y += 220 * delta;
    velocity.scale(0.96);
  }
}

// ===========================================================================
// Score popup (floating text component)
// ===========================================================================

class ScorePopup extends TextComponent with HasGameReference<BubblePopGame> {
  ScorePopup({
    required Vector2 position,
    required String text,
    required Color color,
    this.big = false,
  }) : super(
         position: position,
         anchor: Anchor.center,
         text: text,
         textRenderer: TextPaint(
           style: TextStyle(
             color: color,
             fontSize: big ? 30 : 20,
             fontWeight: FontWeight.w900,
             decoration: TextDecoration.none,
             fontFamily: kFontFamily,
             shadows: [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 10)],
           ),
         ),
       );

  final bool big;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    scale = Vector2.all(0.4);
    add(
      ScaleEffect.to(Vector2.all(1.0), EffectController(duration: 0.18, curve: Curves.easeOutBack)),
    );
    add(MoveEffect.by(Vector2(0, -55), EffectController(duration: 0.7, curve: Curves.easeOut)));
    add(
      OpacityEffect.fadeOut(EffectController(duration: 0.7, startDelay: 0.1))
        ..onComplete = () => removeFromParent(),
    );
  }
}

// ===========================================================================
// Ripple (tap feedback)
// ===========================================================================

class RippleComponent extends PositionComponent {
  RippleComponent({required Vector2 position, required this.color})
    : super(position: position, anchor: Anchor.center);

  final Color color;
  double _r = 6;
  double _life = 0;

  @override
  void update(double dt) {
    _life += dt;
    _r += 180 * dt;
    if (_life > 0.4) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = (1 - _life / 0.4) * 0.5;
    canvas.drawCircle(
      Offset.zero,
      _r,
      Paint()
        ..color = color.withValues(alpha: a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
}

// ===========================================================================
// Flame Game
// ===========================================================================

class BubblePopGame extends FlameGame with TapCallbacks {
  BubblePopGame({required this.score});

  final ScoreModel score;

  GameState state = GameState.ready;
  late OceanBackground background;
  late Component bubbleLayer;
  late Component particleLayer;
  late Component popupLayer;

  double _spawnTimer = 0;
  double _levelUpFlashTime = 0;
  int _lastShownLevel = 1;

  double _shakeAmount = 0;
  final List<VoidCallback> _onStateChange = [];

  void addStateListener(VoidCallback cb) => _onStateChange.add(cb);
  void removeStateListener(VoidCallback cb) => _onStateChange.remove(cb);

  void _notifyState() {
    for (final cb in List.of(_onStateChange)) {
      cb();
    }
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    background = OceanBackground();
    _backgroundInitialized = true;
    add(background);

    bubbleLayer = Component();
    add(bubbleLayer);
    particleLayer = Component();
    add(particleLayer);
    popupLayer = Component();
    add(popupLayer);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // onGameResize 可能在 onLoad 之前被调用，此时 background 尚未初始化
    if (_backgroundInitialized) {
      background.resize(size);
    }
  }

  bool _backgroundInitialized = false;

  void startGame() {
    bubbleLayer.removeAll(bubbleLayer.children);
    particleLayer.removeAll(particleLayer.children);
    popupLayer.removeAll(popupLayer.children);

    score.reset();
    _spawnTimer = 0;
    _lastShownLevel = 1;
    _levelUpFlashTime = 0;
    _shakeAmount = 0;
    camera.viewfinder.position = Vector2.zero();
    resumeEngine();
    state = GameState.playing;
    _notifyState();
  }

  void pauseGame() {
    if (state == GameState.playing) {
      state = GameState.paused;
      pauseEngine();
      _notifyState();
    }
  }

  void resumeGame() {
    if (state == GameState.paused) {
      state = GameState.playing;
      resumeEngine();
      _notifyState();
    }
  }

  void quitToReady() {
    bubbleLayer.removeAll(bubbleLayer.children);
    particleLayer.removeAll(particleLayer.children);
    popupLayer.removeAll(popupLayer.children);
    score.reset();
    _levelUpFlashTime = 0;
    _shakeAmount = 0;
    camera.viewfinder.position = Vector2.zero();
    resumeEngine();
    state = GameState.ready;
    _notifyState();
  }

  void endGame() {
    if (state == GameState.gameOver) return;
    state = GameState.gameOver;
    score.commitBest();
    spawnExplosion(
      Vector2(size.x / 2, size.y / 2),
      kColDanger,
      count: 40,
      speed: 320,
      life: 0.9,
      particleSize: 6,
    );
    playSound('game_over');
    vibrate();
    _notifyState();
  }

  void restart() => startGame();

  // ---------- Spawning ----------

  BubbleComponent _spawnBubble() {
    final level = score.level;
    final rLow = bubbleRadiusLow(level);
    final rHigh = bubbleRadiusHigh(level);
    final radius = rLow + _rng.nextDouble() * (rHigh - rLow);

    final margin = radius + 8;
    final x = margin + _rng.nextDouble() * (size.x - margin * 2);
    final y = size.y + radius + 10;

    final roll = _rng.nextDouble();
    BubbleKind kind;
    if (roll < bombChanceFor(level)) {
      kind = BubbleKind.bomb;
    } else if (roll < bombChanceFor(level) + kBonusChance) {
      kind = BubbleKind.bonus;
    } else {
      kind = BubbleKind.normal;
    }

    final List<Color> grad;
    if (kind == BubbleKind.bomb) {
      grad = [const Color(0xFF4A5568), const Color(0xFF1A202C)];
    } else if (kind == BubbleKind.bonus) {
      grad = [const Color(0xFFFFE066), const Color(0xFFFF9F1C)];
    } else {
      grad = kBubbleGradients[_rng.nextInt(kBubbleGradients.length)];
    }

    final rise = riseSpeedFor(level) * (0.85 + _rng.nextDouble() * 0.4);
    final driftAmp = (level >= 3 ? 18.0 + (level - 3) * 6 : 8.0) * _rng.nextDouble();
    final driftFreq = 1.0 + _rng.nextDouble() * 1.5;

    return BubbleComponent(
      kind: kind,
      radius: radius,
      position: Vector2(x, y),
      riseSpeed: rise,
      driftAmp: driftAmp,
      driftFreq: driftFreq,
      gradient: grad,
    );
  }

  // ---------- Game Loop ----------

  @override
  void update(double dt) {
    super.update(dt);

    // Decay screen shake (applied to camera)
    if (_shakeAmount > 0) {
      _shakeAmount = max(0, _shakeAmount - dt * 60);
      camera.viewfinder.position = Vector2(
        (_rng.nextDouble() * 2 - 1) * _shakeAmount,
        (_rng.nextDouble() * 2 - 1) * _shakeAmount,
      );
      if (_shakeAmount <= 0) {
        camera.viewfinder.position = Vector2.zero();
      }
    }

    if (state != GameState.playing) return;

    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      final interval = spawnIntervalFor(score.level);
      _spawnTimer = interval * (0.8 + _rng.nextDouble() * 0.4);
      final burst = (score.level >= 4 && _rng.nextDouble() < 0.18) ? 2 : 1;
      for (int i = 0; i < burst; i++) {
        bubbleLayer.add(_spawnBubble());
      }
    }

    if (score.level > _lastShownLevel) {
      _lastShownLevel = score.level;
      triggerLevelUp();
    }

    if (_levelUpFlashTime > 0) {
      _levelUpFlashTime -= dt;
    }

    if (score.isGameOver) {
      endGame();
    }
  }

  void triggerLevelUp() {
    _levelUpFlashTime = 1.2;
    popupLayer.add(
      ScorePopup(
        position: Vector2(size.x / 2, size.y * 0.42),
        text: 'LEVEL ${score.level}',
        color: kColAccent,
        big: true,
      ),
    );
    playSound('levelup');
  }

  // ---------- Input ----------

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (state != GameState.playing) return;

    final pos = event.localPosition;
    final bubbles = bubbleLayer.children.whereType<BubbleComponent>().toList();
    BubbleComponent? hit;
    for (int i = bubbles.length - 1; i >= 0; i--) {
      final b = bubbles[i];
      if (b.isPopped) continue;
      final local = b.absoluteToLocal(pos);
      if (local.distanceTo(Vector2.zero()) <= b.radius) {
        hit = b;
        break;
      }
    }

    if (hit == null) {
      score.breakComboGently();
      final ripple = RippleComponent(
        position: pos.clone(),
        color: kColAccent.withValues(alpha: 0.5),
      );
      particleLayer.add(ripple);
      return;
    }

    onBubbleTapped(hit);
  }

  // ---------- Tap collision logic ----------

  void onBubbleTapped(BubbleComponent b) {
    if (b.isPopped) return;
    switch (b.kind) {
      case BubbleKind.normal:
        const base = 50;
        score.registerCollect(base);
        b.pop();
        popupLayer.add(
          ScorePopup(
            position: b.position.clone(),
            text: '+${base * score.multiplier}',
            color: b.gradient[0],
          ),
        );
        if (score.combo > 0 && score.combo % 5 == 0) {
          popupLayer.add(
            ScorePopup(
              position: Vector2(b.position.x, b.position.y - 28),
              text: 'COMBO x${score.multiplier}',
              color: kColGold,
              big: true,
            ),
          );
          spawnPopParticles(b.position, kColGold, BubbleKind.bonus, count: 18);
        }
        playSound('pop');
        vibrate();
        break;
      case BubbleKind.bonus:
        const base = 200;
        score.registerCollect(base);
        b.pop();
        popupLayer.add(
          ScorePopup(
            position: b.position.clone(),
            text: '+${base * score.multiplier}',
            color: kColGold,
            big: true,
          ),
        );
        spawnPopParticles(b.position, kColGold, BubbleKind.bonus, count: 22, speed: 240);
        playSound('bonus');
        vibrate();
        break;
      case BubbleKind.bomb:
        score.registerBombHit();
        b.pop();
        spawnExplosion(b.position, kColDanger, count: 24, speed: 260, life: 0.6, particleSize: 5);
        popupLayer.add(
          ScorePopup(position: b.position.clone(), text: 'OOPS!', color: kColDanger, big: true),
        );
        _shakeAmount = 12;
        playSound('bomb');
        vibrate();
        break;
    }
  }

  void onBubbleEscaped(BubbleComponent b) {
    if (b.kind.isCollectible) {
      score.registerMiss();
      popupLayer.add(
        ScorePopup(position: Vector2(b.position.x, 40), text: 'MISS', color: kColDanger),
      );
      playSound('miss');
    }
  }

  void onBombEscaped(BubbleComponent b) {
    score.registerBombEscape();
  }

  // ---------- Particles ----------

  void spawnPopParticles(Vector2 pos, Color color, BubbleKind kind, {int? count, double? speed}) {
    final c = count ?? (kind == BubbleKind.bonus ? 18 : (kind == BubbleKind.bomb ? 20 : 12));
    final s = speed ?? (kind == BubbleKind.bonus ? 220 : 180);
    final burst = ParticleBurst(
      position: pos.clone(),
      color: color,
      count: c,
      speed: s,
      life: 0.5,
      particleSize: kind == BubbleKind.bonus ? 5 : 3.5,
    );
    particleLayer.add(burst);
  }

  void spawnExplosion(
    Vector2 pos,
    Color color, {
    int count = 20,
    double speed = 200,
    double life = 0.6,
    double particleSize = 4,
  }) {
    particleLayer.add(
      ParticleBurst(
        position: pos.clone(),
        color: color,
        count: count,
        speed: speed,
        life: life,
        particleSize: particleSize,
      ),
    );
  }

  bool get showLevelUpFlash => _levelUpFlashTime > 0;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_levelUpFlashTime > 0) {
      final a = _clamp(_levelUpFlashTime / 1.2, 0, 1) * 0.25;
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = kColAccent.withValues(alpha: a),
      );
    }
  }
}

// ===========================================================================
// Flutter UI Layer
// ===========================================================================

class BubblePopApp extends StatefulWidget {
  const BubblePopApp({super.key});

  @override
  State<BubblePopApp> createState() => _BubblePopAppState();
}

class _BubblePopAppState extends State<BubblePopApp> with WidgetsBindingObserver {
  late final BubblePopGame _game;
  late final ScoreModel _score;

  @override
  void initState() {
    super.initState();
    _score = ScoreModel();
    _game = BubblePopGame(score: _score);
    _game.addStateListener(_onStateChanged);
    WidgetsBinding.instance.addObserver(this);
    // 首帧后再添加初始 overlay，此时 GameWidget 的 overlayBuilderMap 已注册。
    // 不使用 initialActiveOverlays，因为 Flame 1.38 的 GameWidget 构造函数
    // 会在每次 widget 重建时重新应用它，导致已移除的 overlay 被加回。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onStateChanged();
    });
  }

  void _onStateChanged() {
    if (!mounted) return;
    final g = _game;
    g.overlays.clear();
    switch (g.state) {
      case GameState.ready:
        g.overlays.add('start');
        break;
      case GameState.playing:
        g.overlays.add('hud');
        break;
      case GameState.paused:
        g.overlays.add('hud');
        g.overlays.add('pause');
        break;
      case GameState.gameOver:
        g.overlays.add('gameover');
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _game.pauseGame();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.removeStateListener(_onStateChanged);
    _score.dispose();
    _game.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kGameTitle,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: kFontFamily,
        scaffoldBackgroundColor: kColBgBottom,
        colorScheme: const ColorScheme.dark(
          primary: kColAccent,
          secondary: kColAccent2,
          surface: kColBgBottom,
        ),
      ),
      home: SafeArea(
        top: true,
        bottom: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return GameWidget(
                game: _game,
                backgroundBuilder: (ctx) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [kColBgTop, kColBgMid, kColBgBottom],
                    ),
                  ),
                ),
                overlayBuilderMap: {
                  'start': (ctx, g) => _StartOverlay(score: _score, onStart: _game.startGame),
                  'hud': (ctx, g) => _HudOverlay(score: _score, onPause: _game.pauseGame),
                  'pause': (ctx, g) => _PauseOverlay(
                    onResume: _game.resumeGame,
                    onRestart: _game.startGame,
                    onQuit: _game.quitToReady,
                  ),
                  'gameover': (ctx, g) =>
                      _GameOverOverlay(score: _score, onPlayAgain: _game.restart),
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Start Overlay
// ===========================================================================

class _StartOverlay extends StatelessWidget {
  const _StartOverlay({required this.score, required this.onStart});
  final ScoreModel score;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            kColBgTop.withValues(alpha: 0.55),
            kColBgMid.withValues(alpha: 0.75),
            kColBgBottom.withValues(alpha: 0.92),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BubbleLogo(),
                const SizedBox(height: 24),
                ShaderMask(
                  shaderCallback: (bounds) =>
                      const LinearGradient(colors: [kColAccent, kColAccent2]).createShader(bounds),
                  child: const Text(
                    kGameTitle,
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  kGameSubtitle,
                  style: TextStyle(
                    fontSize: 14,
                    letterSpacing: 8,
                    color: kColTextDim,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 40),
                _BestScoreChip(best: score.best),
                const SizedBox(height: 36),
                _PressStartButton(onTap: onStart),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Tap colorful bubbles to score.\nAvoid the bombs.\nDon\'t let bubbles escape!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kColTextDim,
                      fontSize: 14,
                      height: 1.5,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleLogo extends StatelessWidget {
  const _BubbleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [kColAccent.withValues(alpha: 0.55), kColAccent2.withValues(alpha: 0.0)],
              ),
              boxShadow: [
                BoxShadow(
                  color: kColAccent.withValues(alpha: 0.45),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kColAccent, kColAccent2],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 14, left: 16),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BestScoreChip extends StatelessWidget {
  const _BestScoreChip({required this.best});
  final int best;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events, color: kColGold, size: 22),
          const SizedBox(width: 8),
          Text(
            'BEST  $best',
            style: const TextStyle(
              color: kColWhite,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _PressStartButton extends StatefulWidget {
  const _PressStartButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_PressStartButton> createState() => _PressStartButtonState();
}

class _PressStartButtonState extends State<_PressStartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [kColAccent, kColAccent2],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: kColAccent.withValues(alpha: 0.5),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
              SizedBox(width: 8),
              Text(
                'START GAME',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// HUD Overlay
// ===========================================================================

class _HudOverlay extends StatelessWidget {
  const _HudOverlay({required this.score, required this.onPause});
  final ScoreModel score;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _ScoreCard(score: score)),
                const SizedBox(width: 10),
                _PauseButton(onTap: onPause),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ComboChip(combo: score.combo, mult: score.multiplier),
                const SizedBox(width: 8),
                _LevelChip(level: score.level),
                const Spacer(),
                _LivesIndicator(lives: score.lives),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score});
  final ScoreModel score;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: score,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SCORE',
                        style: TextStyle(
                          color: kColTextDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Text(
                          '${score.score}',
                          key: ValueKey(score.score),
                          style: const TextStyle(
                            color: kColWhite,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                            shadows: [Shadow(color: kColAccent, blurRadius: 14)],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'BEST',
                        style: TextStyle(
                          color: kColTextDim,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      Text(
                        '${score.best}',
                        style: const TextStyle(
                          color: kColGold,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: const Icon(Icons.pause_rounded, color: kColWhite, size: 26),
      ),
    );
  }
}

class _ComboChip extends StatelessWidget {
  const _ComboChip({required this.combo, required this.mult});
  final int combo;
  final int mult;

  @override
  Widget build(BuildContext context) {
    final active = combo >= 3;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? kColGold.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? kColGold.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: active ? kColGold : kColTextDim, size: 16),
          const SizedBox(width: 6),
          Text(
            'x$mult',
            style: TextStyle(
              color: active ? kColGold : kColTextDim,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        'LV $level',
        style: const TextStyle(
          color: kColWhite,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _LivesIndicator extends StatelessWidget {
  const _LivesIndicator({required this.lives});
  final int lives;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(kStartLives, (i) {
        final filled = i < lives;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            Icons.favorite,
            color: filled ? kColDanger : Colors.white.withValues(alpha: 0.15),
            size: 20,
          ),
        );
      }),
    );
  }
}

// ===========================================================================
// Pause Overlay
// ===========================================================================

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onRestart, required this.onQuit});
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          margin: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: kColBgMid.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PAUSED',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: kColWhite,
                  letterSpacing: 4,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 24),
              _DialogButton(
                label: 'RESUME',
                icon: Icons.play_arrow_rounded,
                gradient: const [kColAccent, kColAccent2],
                onTap: onResume,
              ),
              const SizedBox(height: 12),
              _DialogButton(
                label: 'RESTART',
                icon: Icons.refresh_rounded,
                gradient: const [Color(0xFF334155), Color(0xFF1E293B)],
                onTap: onRestart,
              ),
              const SizedBox(height: 12),
              _DialogButton(
                label: 'QUIT',
                icon: Icons.home_rounded,
                gradient: const [Color(0xFF475569), Color(0xFF334155)],
                onTap: onQuit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: gradient),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Game Over Overlay
// ===========================================================================

class _GameOverOverlay extends StatefulWidget {
  const _GameOverOverlay({required this.score, required this.onPlayAgain});
  final ScoreModel score;
  final VoidCallback onPlayAgain;

  @override
  State<_GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<_GameOverOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<int> _scoreAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );
    final target = widget.score.score;
    _scoreAnim = IntTween(begin: 0, end: target).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
      ),
    )..addListener(() => setState(() {}));
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              padding: const EdgeInsets.all(28),
              margin: const EdgeInsets.symmetric(horizontal: 30),
              decoration: BoxDecoration(
                color: kColBgMid.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: kColDanger.withValues(alpha: 0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: kColDanger.withValues(alpha: 0.35),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'GAME OVER',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: kColDanger,
                        letterSpacing: 4,
                        decoration: TextDecoration.none,
                        shadows: [Shadow(color: kColDanger, blurRadius: 18)],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'FINAL SCORE',
                      style: TextStyle(
                        color: kColTextDim,
                        fontSize: 13,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_scoreAnim.value}',
                      style: const TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        color: kColWhite,
                        decoration: TextDecoration.none,
                        shadows: [Shadow(color: kColAccent, blurRadius: 18)],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emoji_events, color: kColGold, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'BEST  ${widget.score.best}',
                          style: const TextStyle(
                            color: kColGold,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (widget.score.maxCombo > 0)
                      Text(
                        'MAX COMBO  x${1 + (widget.score.maxCombo ~/ 5)}',
                        style: TextStyle(
                          color: kColTextDim,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    const SizedBox(height: 28),
                    _DialogButton(
                      label: 'PLAY AGAIN',
                      icon: Icons.refresh_rounded,
                      gradient: const [kColAccent, kColAccent2],
                      onTap: widget.onPlayAgain,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Main
// ===========================================================================

// void main() {
//   runApp(const BubblePopApp());
// }
