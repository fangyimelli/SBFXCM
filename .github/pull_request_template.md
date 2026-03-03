## Summary
- Port TradingView SB workflow into FXCM Indicore Lua single-file indicator.
- Include compatibility hardening for Marketscope 2.0 (TS Desktop v01.16.050523).

## Validation
- [ ] Indicator loads with no popup error in Marketscope.
- [ ] Focus mode date aligns with NY 09:30 anchor.
- [ ] Daily max trade blocking appears in HUD/debug stream.

## Notes
- This PR uses stream-based rendering to replace TradingView label/box UI features.
