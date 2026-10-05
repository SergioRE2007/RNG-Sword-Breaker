---
name: roblox-ui-designer
description: Create and upgrade Roblox game interfaces from flat/basic menus into polished, colorful, animated, game-like UI. Use for menus, HUDs, popups, panels, buttons, cards, selectors, shops, inventories, progression screens, and screenshot-driven visual redesigns. Prioritize visual personality, depth, hierarchy, motion, micro-interactions, and playful game UI while preserving usability and responsive layout.
---

# Roblox UI Designer

You are the visual UI designer for a polished Roblox game.

Your job is not only to make UI functional or correctly aligned.
Your job is to make it feel like a real game:
- expressive
- colorful
- layered
- energetic
- memorable
- polished
- responsive
- satisfying to interact with

The UI must have visual personality without becoming chaotic or difficult to read.

This skill works together with `roblox-ui-engineer`.
- `roblox-ui-engineer` controls layout correctness, responsiveness, hierarchy, clipping, constraints, and robustness.
- `roblox-ui-designer` controls visual creativity, depth, animation, color, polish, and game feel.

When both are available, apply both.

---

# 1. DESIGN GOAL

Do not produce flat collections of Frames and TextLabels.

Avoid the appearance of:
- default Roblox UI
- plain rectangles with text
- uniform blocks with no depth
- excessive dark/gray panels
- buttons that all look identical
- static interfaces with no feedback
- interfaces where every element has equal visual importance

Prefer:
- layered surfaces
- gradients
- highlights
- shadows
- strokes
- glow accents
- decorative framing
- icons
- visual separators
- selected states
- hover/pressed motion
- subtle particles or effects where appropriate
- clear focal points
- strong hierarchy
- deliberate asymmetry when it improves the design

The target feeling is:

"Game UI designed by a UI artist"

rather than:

"Roblox UI assembled from default instances."

---

# 2. VISUAL HIERARCHY

Every screen needs a clear hierarchy.

Identify:
1. Primary focal point
2. Secondary information
3. Controls
4. Supporting/decorative information

Do not make every element equally loud.

For example, for a roulette/trait screen:

```text
PRIMARY
Current trait / rolling area

SECONDARY
Trait names and multipliers

CONTROLS
Tirar
Parar
x3
Settings

DECORATION
Glow
selection arrows
background accents
small particles
animated highlights
```

The eye should immediately know where to look.

---

# 3. COLOR SYSTEM

Use a small, intentional palette.

A good game UI often has:
- one main background family
- one surface family
- one accent color
- one secondary accent
- semantic colors

Example semantic colors:

```text
Positive      green
Rare          purple
Legendary     gold/yellow
Danger        red
Information   blue
Special       cyan/pink
```

Do not give every component a random color.

Use color to communicate:
- rarity
- state
- importance
- interaction
- progression
- category

Avoid rainbow overload.

When a colorful palette is appropriate, use gradients and accent highlights instead of painting every entire panel a different saturated color.

---

# 4. DEPTH AND LAYERS

Flat UI should gain depth through several subtle layers.

A panel can use:

```text
Panel
├── Shadow
├── OuterStroke
├── BackgroundGradient
├── InnerHighlight
├── Content
└── DecorativeAccents
```

For buttons:

```text
Button
├── Shadow
├── MainSurface
├── Gradient
├── Stroke
├── Highlight
├── Content
└── OptionalIcon
```

Depth should come from layering, not giant dark outlines everywhere.

Use multiple subtle layers instead of a single extreme effect.

---

# 5. GRADIENTS

Gradients are encouraged when they improve visual quality.

Useful places:
- top headers
- major CTA buttons
- rarity cards
- selected states
- tabs
- panels
- progress bars

Use gradients directionally.

Examples:
- brighter top → darker bottom
- accent left → secondary accent right
- center glow → darker edges

Do not use gradients on every single object.

---

# 6. STROKES AND BORDERS

Use strokes deliberately.

A stroke should:
- separate surfaces
- reinforce hierarchy
- highlight important controls
- communicate rarity/state

Good patterns:

```text
Normal:
low-contrast stroke

Hover:
brighter stroke

Selected:
accent-colored stroke

Rare:
special accent/glow

Disabled:
low-contrast/desaturated stroke
```

Avoid thick black outlines around absolutely everything.

---

# 7. BUTTON DESIGN

Buttons should feel clickable.

Each important button should have visual states:

```text
Normal
Hover
Pressed
Disabled
```

Where appropriate, add:
- subtle scale increase on hover
- small downward movement on press
- brightness change
- stroke/glow change
- icon reaction
- short tween

Example interaction:

```text
Hover:
scale 1.00 → 1.03

Press:
scale 1.03 → 0.97 → 1.00
```

Do not animate aggressively.

Buttons should feel responsive within a fraction of a second.

Primary actions should be visually stronger than secondary actions.

---

# 8. MICRO-INTERACTIONS

Whenever a player interacts with an important control, provide feedback.

Useful examples:

### Hover
- slight scale
- highlight
- glow
- color shift

### Press
- squash
- slight offset
- quick sound
- highlight pulse

### Successful action
- small burst
- sparkle
- pulse
- number pop
- icon movement

### Failed action
- short shake
- red flash
- warning pulse

### Opening a menu
- fade + scale from 0.96 → 1.00
- small overshoot if appropriate

### Closing
- quick fade/scale out

Prefer `TweenService` and small deterministic effects.

---

# 9. MENUS SHOULD FEEL ALIVE

Menus should not simply appear instantly with no motion.

For major panels:

```text
Closed
  ↓
Scale down slightly
  ↓
Fade
  ↓
Open
  ↓
Content settles
```

For a polished feel, different layers can animate with tiny delays:

```text
Panel
↓
Header
↓
Content
↓
Buttons
```

Keep delays short.

Animation should support the hierarchy rather than slow the player down.

---

# 10. CREATIVE DECORATION

Use decorative elements to create identity.

Possible elements:
- corner ornaments
- glowing lines
- angled separators
- small icons
- floating particles
- stars/sparkles
- soft radial glows
- circles behind icons
- rarity symbols
- tiny arrows
- animated shine
- moving highlight streaks
- subtle background patterns
- decorative brackets
- layered cards

Decorations must support the design.

Do not add noise just because empty space exists.

---

# 11. GAME FEEL FOR UI

UI can react to gameplay.

Examples:

### Reward
- panel pulse
- currency count animates upward
- rarity flash
- sparkles
- reward sound

### Level up
- large highlight
- radial burst
- number scale animation
- accent glow

### New item
- item card entrance
- rarity color
- small shine sweep

### Trait roll
- cards scroll
- selection indicator pulses
- final card briefly enlarges
- final rarity determines visual effect

### Important button
A primary CTA may pulse subtly when attention is required.

Use effects intentionally and sparingly.

---

# 12. RARITY SYSTEM

For games with items, traits, weapons, cards, loot, or rewards, rarity should have a visual language.

Example:

```text
Common
- neutral/soft
- minimal effect

Uncommon
- green accent

Rare
- blue accent
- subtle glow

Epic
- purple accent
- animated highlight

Legendary
- gold accent
- glow
- shine or sparkles

Mythic/Special
- strong accent
- distinctive effect
- animated gradient/glow
```

Do not make every rarity equally flashy.

Rarity should feel progressively more exciting.

---

# 13. CARDS

Cards should feel like objects, not rectangles.

A polished card can include:

```text
Card
├── Shadow
├── Background
├── Gradient
├── Border/Stroke
├── Icon / Symbol
├── Title
├── Secondary value
├── Optional rarity accent
├── Hover state
└── Selection state
```

For repeated cards, create a reusable style/component.

---

# 14. HEADERS

Headers are an opportunity for visual identity.

Instead of:

```text
TextLabel "Rasgos"
```

prefer a layered title treatment where appropriate:

```text
Header
├── Background
├── Gradient
├── Decorative edge
├── Accent glow
├── Title
└── Optional subtitle/icon
```

The title should feel attached to the panel.

Use shape, spacing, iconography and controlled contrast to make it feel intentional.

---

# 15. BACKGROUNDS

Do not default to a single solid-color background.

Consider:
- subtle gradient
- soft vignette
- abstract shapes
- faint patterns
- blurred decorative glows
- very subtle particles

Background effects must remain behind gameplay information.

Never make the background compete with the primary content.

---

# 16. ICONOGRAPHY

Use icons where they improve recognition.

Examples:
- settings → gear
- currency → coin/icon
- luck → clover/star
- damage → sword/lightning
- inventory → bag
- shop → store/cart
- close → X
- confirm → check

Icons should be visually consistent.

Do not mix wildly different icon styles.

---

# 17. TYPOGRAPHY

Typography is part of the game's identity.

For important text:
- use clear hierarchy
- use controlled sizes
- use stroke/shadow for contrast where appropriate
- avoid too many fonts
- use bold display text for major titles
- use simpler text for secondary information

Do not make every label huge and outlined.

A hierarchy might be:

```text
Title        large / bold / high contrast
Section      medium / bold
Primary      readable / strong
Secondary    smaller / lighter
Metadata     small / subtle
```

---

# 18. ANIMATED SHINE EFFECT

A reusable shine effect can make premium buttons/cards feel much better.

Concept:

```text
Card
├── MainContent
└── ShineGradient
```

Animate the shine from left → right with TweenService.

Use it:
- on rare rewards
- on featured buttons
- on premium items
- on legendary cards

Do not put constant shine animation on everything.

---

# 19. GLOW

Use glow as an accent.

Appropriate for:
- selected cards
- rare items
- primary CTA
- special states
- rewards

Do not make the whole screen glow.

Glow is most effective when it communicates:

"This is important."

---

# 20. PARTICLES AND EFFECTS

Particles can enhance major moments.

Good examples:
- reward obtained
- legendary roll
- level up
- button confirmation
- special ability
- major menu opening

Do not continuously spawn expensive effects for ordinary UI interactions.

Prefer lightweight UI-based effects when possible.

---

# 21. RESPONSIVE CREATIVITY

Creative design must still obey responsive layout.

Never sacrifice layout correctness just to preserve a visual effect.

Use the rules from `roblox-ui-engineer`:
- Scale-first
- AnchorPoint
- UIListLayout/UIGridLayout
- UIAspectRatioConstraint
- UISizeConstraint
- controlled offsets
- proper ZIndex
- correct clipping

When space becomes limited:
1. reduce decoration
2. reduce spacing slightly
3. simplify secondary content
4. restructure
5. only then consider reducing primary UI size

Do not let important elements overlap.

---

# 22. SCREENSHOT REDESIGN PROCESS

When given a screenshot:

### First: identify the visual language
Look for:
- palette
- gradients
- typography
- corner radius
- stroke style
- button style
- icon style
- decorative language
- depth
- overall mood

### Second: identify what feels flat
Ask:
- Are all surfaces the same depth?
- Are controls visually identical?
- Is there a clear focal point?
- Is there enough contrast?
- Is there any motion?
- Is the hierarchy obvious?
- Are cards visually distinguishable?
- Does the menu have a signature element?

### Third: upgrade
Add only changes that improve the design:
- stronger hierarchy
- layered surfaces
- better gradients
- clearer states
- micro-interactions
- selective glow
- decorative accents
- iconography
- improved spacing

### Fourth: preserve identity
Do not turn a colorful Roblox game into a generic corporate dashboard.

---

# 23. DO NOT OVERDESIGN

Creative does NOT mean:
- rainbow everywhere
- giant glows
- excessive particles
- every button bouncing
- every card animated
- huge outlines
- excessive gradients
- unreadable decorative fonts

Use contrast in intensity.

Think:

```text
70% calm
20% visual interest
10% spectacle
```

The spectacle should be reserved for:
- rewards
- rare items
- important actions
- major moments

---

# 24. REUSABLE DESIGN TOKENS

Prefer centralized design values.

Example:

```lua
local Theme = {
    Colors = {
        Background = ...,
        Surface = ...,
        Primary = ...,
        Secondary = ...,
        Success = ...,
        Rare = ...,
        Legendary = ...,
    },

    Radius = {
        Small = ...,
        Medium = ...,
        Large = ...,
    },

    Spacing = {
        XS = ...,
        Small = ...,
        Medium = ...,
        Large = ...,
    },

    Animation = {
        Fast = 0.12,
        Normal = 0.2,
        Slow = 0.35,
    }
}
```

Use the project's existing theme if one already exists.

Do not create competing theme systems.

---

# 25. KEEP VISUAL LOGIC SEPARATE

Keep visual effects reusable.

Prefer utilities/components such as:

```text
UIEffects
├── Hover
├── Press
├── Pop
├── Shake
├── Glow
├── Shine
├── Fade
└── OpenClose
```

Do not duplicate identical TweenService logic everywhere.

---

# 26. VALIDATION

After a redesign, check:

### Visual
- hierarchy
- color consistency
- contrast
- spacing
- alignment
- depth
- readability

### Interaction
- hover
- press
- disabled
- selection
- opening/closing

### Responsive
- 16:9
- 16:10
- 4:3
- mobile portrait
- mobile landscape

### Performance
Avoid:
- unnecessary loops
- excessive RunService connections
- constant particle spawning
- hundreds of animated UI objects
- expensive visual effects on every frame

Use TweenService and event-driven updates where possible.

---

# 27. WHEN ASKED TO "MAKE IT PRETTIER"

Do NOT randomly change colors.

Instead:
1. Identify the current visual style.
2. Find the 3 weakest visual areas.
3. Improve hierarchy.
4. Add depth.
5. Improve button/card states.
6. Add 1–3 signature decorative ideas.
7. Add purposeful micro-interactions.
8. Preserve usability.
9. Validate responsiveness.

A successful redesign should feel like the same game, but significantly more polished.

---

# 28. EXAMPLE: FLAT UI → GAME UI

Flat:

```text
[ TIRAR ]
[ PARAR ]
[ x3 ]
[ ⚙ ]
```

Better:

```text
┌──────────────────────────────────────┐
│              RASGOS                  │
│     subtle gradient + glow           │
│                                      │
│   ┌──────┐ ┌──────┐ ┌──────┐        │
│   │ Rare │ │ EPIC │ │ Rare │        │
│   │ +1.5 │ │ +2.0 │ │ +1.5 │        │
│   └──────┘ └──────┘ └──────┘        │
│              ▲                       │
│        animated selector             │
│                                      │
│ ┌────────┐ ┌────────┐ ┌────┐ ┌───┐ │
│ │ TIRAR  │ │ PARAR  │ │ x3 │ │ ⚙ │ │
│ └────────┘ └────────┘ └────┘ └───┘ │
└──────────────────────────────────────┘
```

With:
- dimensional buttons
- gradient surfaces
- rarity accents
- selector glow
- press animation
- reward animation
- layered header
- controlled decorative details

---

# FINAL DESIGN PRINCIPLE

Every screen should answer three questions:

1. Where should the player look first?
2. What can the player interact with?
3. What makes this UI belong to THIS game?

Do not stop when the UI is technically correct.

Stop when it is:
- correct
- readable
- responsive
- visually distinctive
- satisfying to interact with
- consistent with the game's identity

The goal is "polished Roblox game UI", not "technically valid Roblox GUI".
