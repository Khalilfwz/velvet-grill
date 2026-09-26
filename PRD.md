# Velvet Grill — Product Requirements Document

## 1. Product Overview

Velvet Grill is a single-brand restaurant e-commerce website for a premium casual dining brand. It supports menu discovery, product customization, wishlist, cart, checkout, pickup and dine-in fulfillment, order history/status, reviews, notifications, and administration.

This is a portfolio project with security-conscious engineering. It is not currently intended to operate as a commercial production restaurant platform.

## 2. Problem Statement

Customers need a clear and trustworthy way to browse the menu, understand product options, place orders for pickup or dine-in, and follow order status.

The system must also prevent client-side manipulation of business-critical values such as price, coupon validity, stock, order ownership, payment state, and authorization.

Administrators need structured operational controls for catalog, restaurant settings, orders, reviews, analytics, and auditability.

## 3. Goals

### Product goals

1. Provide a polished and responsive Velvet Grill ordering experience.
2. Make menu discovery and product customization clear.
3. Support pickup and dine-in fulfillment without delivery or reservation complexity.
4. Provide dummy/simulation payment methods.
5. Provide customer accounts, wishlist, order history, reviews, and notifications.
6. Provide a useful admin workflow.
7. Produce portfolio-quality software that is understandable and maintainable.

### Engineering goals

1. Keep business-critical logic server-authoritative.
2. Enforce access control with server authorization and Supabase RLS.
3. Preserve historical order integrity through snapshots where appropriate.
4. Use migrations for schema changes and seed data for deterministic development data.
5. Keep AI-assisted changes reviewable and reversible through Git.

## 4. Target Users

### Guest

Can browse public restaurant content and menu information without an account.

### Customer

Authenticated user who can manage an account, wishlist, cart, checkout, orders, eligible reviews, and notifications.

### Admin

Restaurant owner/operator responsible for catalog, restaurant settings, order operations, reviews, analytics, and audit records.

There is intentionally no Manager role.

## 5. User Stories

### Discovery

- As a guest, I want to browse the menu by category so I can find food and drinks quickly.
- As a guest, I want to see product descriptions and prices before ordering.
- As a customer, I want to view product options so I can customize an order.

### Account

- As a user, I want to register and log in with email and password.
- As a customer, I want to manage my profile without being able to change my own role.

### Wishlist and Cart

- As a customer, I want to save products to a wishlist.
- As a customer, I want to add products and options to a cart.
- As a customer, I want authoritative pricing to be calculated by the server.

### Checkout and Orders

- As a customer, I want to choose pickup or dine-in fulfillment.
- As a dine-in customer, I want my order associated with a valid restaurant table.
- As a customer, I want to use dummy QRIS, dummy bank transfer, or cash.
- As a customer, I want to see order history and status.
- As a customer, I want order status changes to be recorded historically.

### Reviews and Notifications

- As a customer, I want to review products I am eligible to review after a completed purchase.
- As a customer, I want to see and manage notifications relevant to me.

### Administration

- As an admin, I want to manage products and categories.
- As an admin, I want to manage restaurant settings, business hours, and tables.
- As an admin, I want to manage orders and moderate reviews.
- As an admin, I want to inspect analytics and audit records.

## 6. Functional Requirements

### Catalog

- FR-01: Display active categories.
- FR-02: Display active products grouped by category order.
- FR-03: Provide product detail pages.
- FR-04: Support product images.
- FR-05: Support option groups and option price deltas.

### Authentication and Profiles

- FR-06: Support email/password authentication.
- FR-07: Maintain a 1:1 profile relationship with `auth.users`.
- FR-08: Prevent customer-facing profile updates from changing role or unauthorized account state.

### Wishlist and Cart

- FR-09: Allow customers to create and manage wishlists.
- FR-10: Allow customers to create and manage carts.
- FR-11: Validate that selected options belong to the selected product.
- FR-12: Protect cart writes by ownership and authorization.

### Checkout and Orders

- FR-13: Allow pickup and dine-in orders.
- FR-14: Calculate authoritative pricing server-side.
- FR-15: Preserve required historical product/option snapshots in orders.
- FR-16: Validate coupons server-side.
- FR-17: Model payment state separately from order state.
- FR-18: Record order status history.
- FR-19: Make retry-sensitive order/payment operations idempotent where appropriate.
- FR-20: Validate dine-in table context server-side before finalizing a dine-in order.
- FR-21: Prevent overselling when stock is enabled.

### Reviews, Notifications, Analytics, Audit

- FR-22: Allow reviews only for eligible completed purchases.
- FR-23: Allow customers to view/manage their own notifications.
- FR-24: Keep analytics separate from transactional revenue truth.
- FR-25: Record sensitive admin actions in audit logs.

### Administration

- FR-26: Admins manage categories/products/options/images.
- FR-27: Admins manage business hours, tables, and restaurant settings.
- FR-28: Admins manage orders and moderate reviews.
- FR-29: Admins inspect operational analytics.
- FR-30: Admin authorization is enforced server-side and by database policy where applicable.

## 7. Non-Functional Requirements

### Security

- NFR-01: Browser-provided business-critical values are untrusted and must not be authoritative.
- NFR-02: RLS protects user-owned and admin-only data.
- NFR-03: Secrets stay server-side and outside source control.
- NFR-04: Destructive database/security changes require human approval.
- NFR-05: Security-sensitive changes require relevant tests/review.
- NFR-06: Security design should align with OWASP Top 10:2025 and ASVS 5.0 principles where applicable.

### Reliability and Integrity

- NFR-07: Monetary values use exact numeric representations.
- NFR-08: Historical orders remain understandable if current product data changes.
- NFR-09: Retry-sensitive writes are designed for idempotency.
- NFR-10: Stock mutation, when enabled, is atomic and concurrency-safe.

### Performance

- NFR-11: Avoid unnecessary client-side data fetching.
- NFR-12: Prefer server-side fetching for appropriate catalog/protected data.
- NFR-13: Avoid unnecessary image payload and blocking interaction work.

### Accessibility and UX

- NFR-14: Keyboard navigation and visible focus states are required.
- NFR-15: Motion respects `prefers-reduced-motion`.
- NFR-16: Important state is not communicated by color alone.
- NFR-17: Responsive behavior works across mobile, tablet, and desktop.

### Maintainability

- NFR-18: Preserve strict TypeScript and existing conventions.
- NFR-19: Prefer small, understandable changes over speculative abstraction.
- NFR-20: Database schema changes are represented by migrations.

## 8. Scope

### In scope

- Single restaurant brand
- Catalog and product details
- Product options/images
- Customer accounts
- Wishlist
- Cart
- Pickup and dine-in
- Dine-in table context
- Dummy QRIS
- Dummy bank transfer
- Cash payment
- Coupons
- Orders and order history
- Reviews
- Notifications
- Restaurant tables
- Business hours
- Admin operations
- Analytics
- Admin audit logs
- RLS/security controls

### Out of scope

- Multi-vendor marketplace
- Delivery logistics or driver tracking
- Real payment gateway processing
- Real QRIS transaction processing
- Social login
- Manager role
- Real reservation booking
- Production-grade multi-region infrastructure
- Advanced ML personalization unless separately approved

## 9. Success Criteria

The project is successful when:

1. Core user flows work end-to-end.
2. Business-critical values remain server-authoritative.
3. RLS/security tests pass.
4. UI matches the design system.
5. The repository remains understandable without hidden AI assumptions.
6. Significant AI-assisted changes are reviewable in Git.
7. Deployment does not expose secrets.

## 10. Constraints

- Local-first development.
- Supabase Local for development.
- Git/GitHub for version control.
- AI agents follow the documented workflow and permissions.
- No automated YOLO/bypass workflow for normal development.
