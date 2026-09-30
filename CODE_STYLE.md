# Code style — write it like a person wrote it

Everything in this repo must read as if a developer on the team wrote it.
Nothing may read as if it came out of a tool.

This applies to C#, TypeScript and SQL. It applies to variable names, class
names, API routes, commit messages and above all comments.

If you are using an AI assistant to help, that is fine. But the code that lands
in the repo is our code, and it must look and read like ours.

---

## 1. Why this matters

Code that looks machine written is a problem for real reasons, not just taste.

- It is usually over-commented, so the comments that matter get lost in noise.
- It is uniform in a way real code never is, which hides where the hard parts are.
- It explains the language instead of explaining the business.
- Reviewers skim it, because it all looks the same.

Human code is uneven on purpose. The tricky method has four comments. The
boring one next to it has none. That unevenness is information.

---

## 2. Comments are the biggest giveaway

### Do not comment everything

A tool comments every method. A person comments the ones that need it.

Most methods need no comment at all. If the name says what it does, stop there.

**Wrong**

```csharp
/// <summary>
/// Gets an item by its identifier.
/// </summary>
/// <param name="id">The identifier of the item.</param>
/// <returns>The item, or null if it does not exist.</returns>
public async Task<ItemDTO?> GetById(Guid id)
```

**Right**

```csharp
public async Task<ItemDTO?> GetById(Guid id)
```

The signature already says all of that. The comment added nothing.

### Comment the why, never the what

**Wrong**

```csharp
// Loop through the images and find the primary one
foreach (var image in item.ItemImages)
```

**Right**

```csharp
// Shops sometimes upload a second primary by mistake, so take the first.
foreach (var image in item.ItemImages)
```

The first one tells you what you can already see. The second one tells you
something you could not have known.

### Where comments belong

Put a comment where a reader would otherwise stop and ask "why on earth is it
done like that". Typically:

- A rule that comes from the business and not from the code. Name the decision.
- A workaround. Say what it works around.
- Something that looks wrong but is right. Say why.
- An ordering that matters. Say what breaks if you swap it.

Everywhere else, no comment.

### Write like you talk

Short sentences. Contractions are fine. Not every comment needs a full stop or
a capital letter. Lower case is fine for a one liner.

**Wrong**

```csharp
// It is important to note that this operation must be performed within a
// transaction in order to ensure that the audit record and the state change
// are committed atomically, thereby guaranteeing consistency.
```

**Right**

```csharp
// Audit row has to go in the same transaction or we can lose it.
```

### Words that give it away

Do not use these in comments. They almost never appear in code a person wrote:

> deliberate, deliberately, note that, it is worth noting, crucially,
> importantly, robust, seamless, comprehensive, leverage, utilise, facilitate,
> ensure that, in order to, thereby, hence, moreover, furthermore,
> defence in depth, load bearing, first class, single source of truth

Say the plain version instead. "in order to" is just "to". "utilise" is "use".
"ensure that the list is not empty" is "check the list isn't empty".

### Punctuation

No em dashes in comments. No semicolons joining two clauses. Use a full stop
and start a new sentence, or use brackets.

**Wrong**

```csharp
// The database is the authority here — the API check is a convenience;
// both must agree.
```

**Right**

```csharp
// The database has the final say. We check here first so the user gets a
// proper message instead of a SQL error.
```

### No banner art

No boxes, no rows of dashes or equals signs, no decorated section headers in
C# or TypeScript. A blank line is enough to separate things.

SQL migration files are the one exception. A short header at the top of the
file saying what it creates is normal and useful.

---

## 3. Naming

### Classes

Short. Words from the business, not from a design pattern book.

| Use | Don't use |
|---|---|
| `ItemService` | `ItemManagementService` |
| `Invoice` | `InvoiceEntity`, `InvoiceModel` |
| `BidValidator` | `AbstractBidValidationStrategy` |
| `ShopSettings` | `ShopConfigurationSettingsContainer` |

Two words is normal. Three is sometimes needed. Four means you are describing
the class instead of naming it.

Do not stack suffixes. `IItemRepositoryFactoryProvider` is not a name, it is an
apology.

### Methods

Verbs people say out loud. `Save`, `Close`, `Cancel`, `GetById`, `Reverse`,
`Issue`, `Withdraw`.

Not `PerformItemStateTransitionOperation`. Just `Transition`.

Remember: no `Async` suffix in this codebase, even on async methods. That
matches the Aspiration project.

### Variables

Match the name length to how long the variable lives.

```csharp
// Fine. It exists for one line.
foreach (var x in rows)

// Fine. Short scope, obvious from context.
var dto = ToDto(item, now);

// Needs a real name. This one is used forty lines down.
var outstandingFeeInvoices = await GetUnpaidFees(shopId);
```

Common short names that are fine and that everyone understands:

`id`, `ctx`, `db`, `req`, `res`, `cfg`, `repo`, `dto`, `qty`, `amt`, `idx`,
`tmp`, `i`, `x`, `sql`, `msg`, `err`

A tool spells everything out. A person does not.

### API routes

Short and flat.

```
/api/items
/api/items/{id}/transition
/api/marketplace/items
```

Not `/api/v1/item-management/items/{id}/state-transitions`.

### Booleans

`isPaid`, `hasBids`, `canEdit`. Not `paidStatusIndicator` or `bidExistenceFlag`.

---

## 4. Shape of the code

### Let it be uneven

Real files have a 60 line method and a 3 line method sitting next to each other.
That is fine. Do not split a method just to make everything look the same size.

### Do not validate what cannot be wrong

A private method called from one place, two lines above, does not need a null
check on its argument.

**Wrong**

```csharp
private static ItemDTO ToDto(ItemItem item, DateTimeOffset now)
{
    if (item == null)
    {
        throw new ArgumentNullException(nameof(item));
    }
    ...
}
```

**Right**

```csharp
private static ItemDTO ToDto(ItemItem item, DateTimeOffset now)
{
    ...
}
```

Validate at the edges. The controller and the public service method. Not every
private helper.

### Mix `var` and explicit types

Use `var` when the type is obvious from the right hand side. Write the type out
when it is not. Do not pick one and apply it everywhere, because nobody does
that.

```csharp
var items = new List<ItemDTO>();          // obvious
int total = await query.CountAsync();      // clearer written out
var now = await clock.Now();               // obvious
string? state = await GetState(id);        // the ? matters, spell it out
```

### Group with blank lines by thought

Not by rule. If three lines belong together, keep them together. If the next
bit is a different idea, put a blank line in.

### TODOs

A real TODO has a name and a ticket or a date. An empty TODO is worse than none.

```csharp
// TODO(raman): fee rounding is per line here, spec says per invoice. PHIL-214
```

Only write a TODO for something that is genuinely outstanding. Do not invent
ticket numbers, names or dates. A fake reference is worse than no comment,
because the next person will waste time looking for it.

---

## 5. Errors

Error messages should sound like a person telling you what went wrong.

**Wrong**

```csharp
throw new InvalidOperationException(
    "The requested state transition could not be performed as it does not " +
    "satisfy the configured transition constraints.");
```

**Right**

```csharp
throw new BusinessRuleViolationException(
    "An item can't go from " + fromState + " to " + toState + ".");
```

Do not make every message the same shape. A person writes each one for the
situation it covers.

---

## 6. C#

- Plain classes with `{ get; set; }`. No `record` types.
- No collection expressions. Use `new[] { }` or `new List<T>()`.
- No switch expressions. Use `if` or a normal `switch`.
- No default implementations inside interfaces. Put the code in the class.
- No raw string literals.
- Primary constructors on services are fine. The Aspiration project uses them.
- Break long LINQ into steps with named variables instead of one long chain.
- 4 spaces. File scoped namespaces.

---

## 7. TypeScript and React

- Plain `type` or `interface`. Avoid clever generics and mapped types.
- Do not annotate what TypeScript already knows.
- Small components. A component that renders a card should render a card.
- No comment above every prop.
- Keep helper functions near the bottom of the file where they are used.

**Wrong**

```ts
/**
 * Formats a monetary amount held in minor units into a display string.
 * @param minor - The amount in minor units (cents).
 * @param symbol - The currency symbol to prefix.
 * @returns The formatted string.
 */
export function formatMoney(minor: number, symbol = "R"): string {
```

**Right**

```ts
// Amounts come back from the API in cents.
export function formatMoney(minor: number, symbol = "R"): string {
```

---

## 8. SQL

- A short header at the top of a migration saying what it creates. That is it.
- Comment a constraint only when the reason is not obvious from its name.
- Cite the decision number for business rules. `-- D063: 90 days max.`
- Do not comment every column.

**Wrong**

```sql
-- The unique identifier for the item
ID UNIQUEIDENTIFIER NOT NULL,
-- The identifier of the shop that owns this item
ShopID UNIQUEIDENTIFIER NOT NULL,
```

**Right**

```sql
ID     UNIQUEIDENTIFIER NOT NULL,
ShopID UNIQUEIDENTIFIER NOT NULL,
```

---

## 9. Before you commit

Read your diff and ask:

1. Could I delete half the comments and lose nothing? Then delete them.
2. Does any comment just restate the line under it? Delete it.
3. Is every method the same length with the same comment density? Vary it.
4. Have I used any word from the banned list in section 2? Rewrite it.
5. Are there em dashes in comments? Replace them.
6. Would I say this comment out loud to someone at my desk? If not, rewrite it.
7. Is any name longer than four words? Shorten it.
8. Did I null check something that can never be null? Remove it.

If you generated a file with an assistant, do not commit it as it came out.
Read it, cut the comments back, rename anything that reads like a manual, and
make the shape match the rest of the folder.

---

## 10. One honest note

This is about readability and consistency, not about hiding anything. If
someone asks how the code was written, say so plainly. The point is that the
code should be good enough, and plain enough, that it reads like the work of
the team that owns it, because it is.
