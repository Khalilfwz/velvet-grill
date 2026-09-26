# Velvet Grill — Design System

## 1. Design Direction

Velvet Grill should feel elegant, premium, warm, restrained, informative, contemporary, and classically styled.

Avoid the visual language of generic AI-generated restaurant templates.

## 2. Brand Colors

| Token | Hex | Primary use |
|---|---|---|
| Deep Burgundy | `#5A1E2B` | Brand, primary actions, accents |
| Warm Ivory | `#F5F1E8` | Main background |
| Charcoal | `#171717` | Primary text |
| Surface | `#FFFFFF` | Card/form surfaces |
| Border | `#E5DED2` | Borders/dividers |
| Brand Light | `#7A3342` | Hover/secondary brand state |

Do not introduce new prominent brand colors without explicit approval.

## 3. Typography

### Display

Use Playfair Display for:

- brand wordmark
- page headings
- category headings
- prominent product names

The distinctive `&` character is part of the brand character.

### UI and body

Use Inter for:

- navigation
- buttons
- labels
- prices
- form text
- body copy
- metadata

## 4. Layout and Spacing

Use Tailwind spacing tokens whenever practical.

Preferred rhythm:

- 4: micro spacing
- 8: compact spacing
- 12: standard gaps
- 16: component spacing
- 24: larger separation
- 32–48: section spacing
- 64+: major page separation

Avoid arbitrary values when existing tokens are sufficient.

## 5. Shape and Elevation

Preferred:

- cards: `rounded-xl`
- controls: `rounded-lg` or semantic pill controls
- soft borders
- restrained shadows

Avoid excessive rounded containers, glowing shadows, or stacked decorative effects.

## 6. Interaction

Use interaction to communicate state, hierarchy, or continuity.

Allowed when purposeful:

- subtle hover/focus transitions
- image gallery transitions
- option-selection feedback
- cart confirmation
- accordion/drawer/modal transitions
- skeleton/loading states
- limited scroll reveal

Avoid:

- constant motion
- decorative animation without purpose
- animated gradients
- excessive parallax
- bouncing UI
- interactions that slow task completion

Respect `prefers-reduced-motion`.

## 7. Accessibility

Every interactive component should provide:

- semantic HTML where appropriate
- keyboard navigation
- visible focus state
- accessible names for icon-only buttons
- meaningful image alt text
- reduced-motion behavior
- input-associated error messages
- state communication that does not rely on color alone

## 8. Responsive Design

Build mobile-first.

Support:

- mobile
- tablet
- desktop

Do not merely shrink the desktop layout. Recompose the hierarchy when necessary.

## 9. Product Cards

Prioritize:

1. product image, when available
2. product name
3. short description
4. price
5. primary action

Do not overload cards with metadata.

## 10. Forms

Provide:

- visible labels
- validation feedback
- loading state
- disabled state when appropriate
- accessible errors
- keyboard support

## 11. Anti-Slop Guardrails

Do not add:

- random gradients
- unexplained glassmorphism
- fake AI glow effects
- excessive badges
- excessive pills
- giant rounded containers
- excessive animation
- decorative elements competing with food imagery
- generic filler copy

When uncertain:

> Prefer stronger hierarchy, whitespace, typography, and purposeful interaction over decoration.

## 12. Security and Architecture Boundary

A design change must not weaken:

- authorization
- validation
- server authority
- RLS
- error handling
- auditability
- maintainability
- performance

Interactive UI is allowed to be sophisticated. Business logic remains subject to `ARCHITECTURE.md` and `SECURITY_WORKFLOW.md`.
