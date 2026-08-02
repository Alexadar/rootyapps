# Principles — on-device models as a business strategy

> Crystallised from surveying the open-model landscape and the paid app market around it. General by
> design: model names and app names both date within months; the economics and the traps do not.

---

## 1. The economic argument

**A product that calls an API has a recurring per-user cost, and recurring cost forces recurring
revenue.** Cloud-backed tools subscribe because they must, not because they are greedy.

Run the same model on the device and marginal cost goes to zero. That makes buy-once **structurally
cheaper for you than for a cloud competitor** — a genuine advantage rather than a pricing preference —
and it makes two further claims literally true rather than marketing: works offline, nothing leaves the
device.

**The moat is not the model.** Models are commodities. The moat is that converting one to run well on
device hardware is hard enough that most developers rent an API instead — and thereby inherit the cost
structure that forces them to subscribe.

---

## 2. The licence gate — the same discipline as citation, higher stakes

A wrongly-licensed model in a paid product is legal exposure, not a failed build.

1. **Permissive licence required** — verified on **the weights file actually shipped**, not the
   repository README. Code and weight licences differ more often than expected, and a permissive
   codebase with unstated weights is a genuine unknown, not a green light.
2. **Any non-commercial variant is dead**, however good.
3. **Read the licence text; do not infer it from a badge.** Unverified means it fails.
4. Beware copyleft in particular — some widely-used vision models carry terms fundamentally
   incompatible with closed-source distribution, and their popularity is not protection.

### Training removes the gate entirely

If you train the model yourself on open data, **you own the weights.** No code-vs-weights trap, no
copyleft, no non-commercial clause, no licence archaeology before every release.

This is a larger strategic shift than it first appears: it converts the licence gate from a permanent
constraint into a one-time cost, and it means the available design space is no longer "which checkpoint
exists" but "which job suits a small specialised model."

**Small and specialised beats large and general on device**, every time — it fits the neural engine,
stays resident, doesn't throttle, and keeps the download size defensible.

---

## 3. The honest counterweight: on-device can be slower

For heavy models, a server GPU is faster than a phone by a wide margin. On-device is then **not a pure
win** — you are trading the user's minutes for their privacy and their wallet.

That trade is only obviously good when one of these holds:

| Condition | Why it wins |
|---|---|
| The model is small enough to be **faster** | no upload, no queue, instant — you win outright |
| Cloud round-trip is **unacceptable** | real-time, field use, no signal |
| The data **cannot be uploaded** | confidential, medical, legal, professional obligation |
| **Nobody has trained for the job** | too narrow for a company to bother with |

If none of these holds, you are shipping a slower version of something that already works, and the
review that says so will be about speed.

---

## 4. Being as good as a healthy incumbent is not a business

Users do not care who trained the model — nobody has ever written a review about model provenance.
They review output quality, speed and terms.

So matching a well-run competitor's quality while charging differently is a **weak** position: they can
drop price and you cannot drop further. The advantage has to be **structural**, from the table above,
not merely cheaper.

---

## 5. Check that the ML is the part people pay for

The most important question, and the easiest to skip.

Repeatedly, in markets that look like machine-learning opportunities, **the money sits in the part that
needs no model at all** — the reader rather than the recogniser, the workflow rather than the
extraction, the organisation rather than the intelligence. The recognition problem is expensive to
solve and serves a smaller, free-priced sub-audience; the mundane handling problem is cheap to build
and sustains a high price with long retention.

**Before training anything: confirm that the model is what the buyer is paying for.** Frequently it
isn't, and the correct move is to build the unglamorous half.

---

## 6. Where the platform already gives it away

Some capabilities are shipped free by the OS at good quality. Do not rebuild those — use them, and
spend your effort on the layer above. The value in those areas is the workflow, not the inference.

Conversely, a platform vendor shipping a shallow version of a capability **sets a floor rather than
closing a category** — paid products continue to sell well above it on depth, workflow and output
quality. Presence of a first-party feature is a starting point for the analysis, not a verdict.

---

## 7. Practical checks before committing

- **Weights licence, in writing** — not the repo's licence
- **A real conversion running on the device's neural engine**, verified on physical hardware. An
  unsupported operation silently drops the graph to CPU without erroring, and the product becomes
  unusable rather than broken
- **Measured runtime and memory** for a realistic input on mid-range hardware, not flagship
- **Download size strategy** — large weights need on-demand resources or a first-run fetch, which is
  both a user-experience and a review consideration for anything promising offline operation
- **Rights are not licences** — a permissive model licence says nothing about the legality of what the
  user processes with it
