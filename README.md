# KESSLER: Institutional Risk & Execution Engine

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Status](https://img.shields.io/badge/Status-Operational-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Native_Zig-orange)

Kessler is a high-frequency algorithmic risk management and execution engine designed explicitly for institutional index trading (NAS100/US100). 

It operates by physically decoupling the trading logic from standard retail terminals. At its core, Kessler runs a **Twin Delayed DDPG (TD3)** reinforcement learning architecture, written entirely from scratch in native Zig, bypassing heavy ML frameworks like PyTorch or TensorFlow for absolute zero-latency execution.

## The Architecture (Kessler V3)

Kessler utilizes a hyper-optimized, low-level execution topology:

1. **The Native Zig Tensor Engine (`ml_native.zig`)**: A custom-built matrix multiplication and neural network library. It features custom SIMD-optimized dense layers, Adam optimizers, and a continuous-action space policy gradient.
2. **The Crucible (`k2_crucible.zig`)**: The RL training harness. It simulates millions of ticks of level-2 order flow (CVD, Z-Scores) across thousands of epochs.
3. **The Reward Function (Differential Sharpe Ratio)**: Kessler does not optimize for maximum profit. It optimizes for the smoothest equity curve, strictly enforcing the drawdown rules of proprietary trading firms (Funding Pips, FTMO) via a penalty matrix.

## Enterprise Features

* **Zero-Dependency ML**: No Python. No CUDA. No PyTorch. The neural network forward and backward passes are written in raw Zig, ensuring maximum CPU utilization and no garbage collection pauses.
* **Prop-Firm Compliance Matrix**: Natively designed to pass proprietary trading firm challenges. The TD3 agent is penalized heavily for touching the 3% Daily or 8% Overall drawdown limits.
* **Wyckoff Order Flow Ingestion**: The input state is not just price. It is a 6-dimensional vector including Delta, Cumulative Volume Delta (CVD), and normalized Z-Scores, mapping exactly to Wyckoff institutional accumulation/distribution phases.

## Component Breakdown

* `src/ml_native.zig`: The core Machine Learning mathematical engine and TD3 Agent.
* `src/k2_crucible.zig`: The 3000-Epoch training loop and deterministic holdout validator.
* `kessler_daemon.py`: The legacy Python tracking engine (currently being phased out for the native Zig compiler).

## Disclaimer
This software is built for private institutional execution. Use at your own risk. Past performance does not guarantee future results.
<!-- Kessler V3 Core -->

<!-- commit step 9: 691 -->

<!-- commit step 11: 435 -->

<!-- commit step 12: 915 -->

<!-- commit step 14: 630 -->

<!-- commit step 24: 521 -->

<!-- commit step 26: 628 -->

<!-- commit step 35: 786 -->

<!-- commit step 37: 650 -->

<!-- commit step 43: 291 -->

<!-- commit step 44: 763 -->

<!-- commit step 46: 325 -->

<!-- commit step 50: 966 -->

<!-- commit step 53: 117 -->

<!-- commit step 64: 364 -->

<!-- commit step 69: 560 -->

<!-- commit step 70: 768 -->

<!-- commit step 71: 763 -->

<!-- commit step 72: 421 -->

<!-- commit step 79: 795 -->

<!-- commit step 81: 263 -->

<!-- commit step 82: 820 -->

<!-- commit step 101: 687 -->

<!-- commit step 114: 424 -->

<!-- commit step 119: 114 -->

<!-- commit step 134: 739 -->

<!-- commit step 137: 884 -->

<!-- commit step 141: 671 -->

<!-- commit step 155: 471 -->

<!-- commit step 162: 657 -->

<!-- commit step 172: 410 -->

<!-- commit step 175: 576 -->

<!-- commit step 177: 659 -->

<!-- commit step 179: 886 -->

<!-- commit step 186: 358 -->

<!-- commit step 192: 582 -->

<!-- commit step 193: 607 -->

<!-- commit step 200: 597 -->

<!-- commit step 216: 356 -->

<!-- commit step 219: 997 -->

<!-- commit step 222: 315 -->

<!-- commit step 228: 352 -->

<!-- commit step 230: 480 -->

<!-- commit step 238: 493 -->

<!-- commit step 242: 103 -->

<!-- kessler step 5: 765 -->

<!-- kessler step 8: 723 -->

<!-- kessler step 9: 434 -->

<!-- kessler step 10: 310 -->

<!-- commit step 250: 655 -->

<!-- commit step 254: 270 -->

<!-- commit step 256: 965 -->

<!-- commit step 267: 273 -->

<!-- commit step 272: 521 -->

<!-- kessler step 34: 110 -->

<!-- kessler step 36: 580 -->

<!-- commit step 276: 929 -->

<!-- commit step 277: 609 -->

<!-- kessler step 42: 776 -->

<!-- kessler step 45: 908 -->

<!-- kessler step 46: 819 -->

<!-- kessler step 48: 664 -->

<!-- kessler step 50: 718 -->

<!-- kessler step 53: 885 -->

<!-- kessler step 58: 559 -->

<!-- commit step 299: 758 -->

<!-- kessler step 74: 324 -->

<!-- kessler step 82: 782 -->

<!-- kessler step 83: 113 -->

<!-- kessler step 85: 237 -->

<!-- kessler step 86: 576 -->

<!-- commit step 331: 912 -->

<!-- kessler step 98: 724 -->

<!-- kessler step 99: 872 -->

<!-- commit step 337: 313 -->

<!-- kessler step 102: 242 -->

<!-- commit step 340: 865 -->

<!-- kessler step 108: 336 -->

<!-- commit step 348: 601 -->

<!-- commit step 353: 467 -->

<!-- kessler step 115: 349 -->

<!-- commit step 361: 348 -->

<!-- kessler step 124: 426 -->

<!-- kessler step 125: 790 -->

<!-- kessler step 129: 170 -->

<!-- kessler step 130: 834 -->

<!-- kessler step 131: 858 -->

<!-- kessler step 132: 980 -->

<!-- kessler step 135: 311 -->

<!-- kessler step 138: 505 -->

<!-- commit step 376: 860 -->

<!-- kessler step 143: 899 -->

<!-- kessler step 144: 861 -->

<!-- commit step 383: 234 -->

<!-- kessler step 145: 608 -->

<!-- kessler step 146: 697 -->

<!-- kessler step 149: 661 -->

<!-- commit step 388: 316 -->

<!-- kessler step 153: 936 -->

<!-- kessler step 155: 224 -->

<!-- commit step 397: 724 -->

<!-- kessler step 160: 452 -->

<!-- commit step 399: 998 -->

<!-- kessler step 168: 454 -->

<!-- kessler step 3: 474 -->

<!-- commit step 410: 681 -->

<!-- kessler step 9: 846 -->

<!-- kessler step 10: 976 -->

<!-- kessler step 178: 256 -->

<!-- kessler step 16: 548 -->

<!-- kessler step 184: 323 -->

<!-- commit step 423: 404 -->

<!-- kessler step 186: 864 -->

<!-- kessler step 190: 649 -->

<!-- kessler step 25: 224 -->

<!-- commit step 430: 553 -->

<!-- kessler step 192: 361 -->

<!-- commit step 433: 100 -->

<!-- commit step 435: 536 -->

<!-- kessler step 33: 587 -->

<!-- kessler step 34: 704 -->

<!-- kessler step 36: 877 -->

<!-- kessler step 202: 559 -->

<!-- kessler step 38: 589 -->

<!-- commit step 442: 712 -->

<!-- kessler step 40: 362 -->

<!-- kessler step 206: 627 -->

<!-- commit step 447: 721 -->

<!-- kessler step 210: 291 -->

<!-- kessler step 213: 118 -->

<!-- kessler step 48: 566 -->

<!-- kessler step 218: 686 -->

<!-- kessler step 55: 905 -->

<!-- commit step 464: 428 -->

<!-- kessler step 226: 356 -->

<!-- commit step 465: 207 -->

<!-- kessler step 228: 852 -->

<!-- kessler step 63: 793 -->

<!-- commit step 469: 798 -->

<!-- kessler step 66: 427 -->

<!-- commit step 470: 700 -->

<!-- kessler step 67: 489 -->

<!-- commit step 472: 586 -->

<!-- kessler step 235: 331 -->

<!-- kessler step 70: 642 -->

<!-- kessler step 74: 381 -->

<!-- kessler step 76: 352 -->

<!-- commit step 480: 161 -->

<!-- kessler step 77: 259 -->

<!-- kessler step 82: 894 -->

<!-- kessler step 89: 461 -->

<!-- kessler step 255: 693 -->

<!-- kessler step 257: 804 -->

<!-- kessler step 94: 215 -->

<!-- commit step 498: 853 -->

<!-- kessler step 95: 754 -->

<!-- kessler step 261: 124 -->

<!-- kessler step 97: 642 -->

<!-- commit step 501: 520 -->

<!-- commit step 502: 885 -->

<!-- commit step 504: 244 -->

<!-- kessler step 270: 867 -->

<!-- commit step 508: 252 -->

<!-- kessler step 107: 409 -->

<!-- commit step 513: 702 -->

<!-- kessler step 277: 960 -->

<!-- kessler step 281: 387 -->

<!-- commit step 520: 156 -->

<!-- kessler step 284: 423 -->

<!-- kessler step 120: 356 -->

<!-- commit step 524: 293 -->

<!-- kessler step 1: 814 -->

<!-- kessler step 125: 705 -->

<!-- kessler step 126: 337 -->

<!-- kessler step 127: 726 -->

<!-- kessler step 5: 399 -->

<!-- commit step 533: 272 -->

<!-- kessler step 131: 959 -->

<!-- kessler step 7: 290 -->

<!-- kessler step 8: 880 -->

<!-- kessler step 9: 297 -->

<!-- kessler step 133: 952 -->

<!-- commit step 538: 727 -->

<!-- kessler step 301: 530 -->

<!-- kessler step 302: 504 -->

<!-- kessler step 16: 501 -->

<!-- kessler step 306: 259 -->

<!-- kessler step 17: 210 -->

<!-- kessler step 307: 682 -->

<!-- kessler step 140: 726 -->

<!-- kessler step 21: 967 -->

<!-- kessler step 310: 672 -->

<!-- kessler step 146: 200 -->

<!-- kessler step 147: 790 -->

<!-- kessler step 315: 510 -->

<!-- kessler step 316: 513 -->

<!-- kessler step 31: 153 -->

<!-- kessler step 33: 910 -->

<!-- kessler step 34: 555 -->

<!-- kessler step 156: 441 -->

<!-- kessler step 325: 691 -->

<!-- kessler step 328: 961 -->

<!-- kessler step 335: 275 -->

<!-- kessler step 50: 350 -->

<!-- kessler step 338: 525 -->

<!-- kessler step 340: 620 -->

<!-- kessler step 55: 270 -->

<!-- kessler step 345: 484 -->

<!-- kessler step 350: 417 -->

<!-- kessler step 355: 895 -->

<!-- kessler step 359: 937 -->

<!-- kessler step 75: 140 -->

<!-- kessler step 76: 165 -->

<!-- kessler step 361: 716 -->

<!-- kessler step 366: 264 -->

<!-- kessler step 368: 771 -->

<!-- kessler step 83: 804 -->

<!-- kessler step 371: 293 -->

<!-- kessler step 86: 978 -->

<!-- kessler step 374: 402 -->

<!-- kessler step 89: 700 -->

<!-- kessler step 90: 417 -->

<!-- kessler step 92: 111 -->

<!-- kessler step 93: 481 -->

<!-- kessler step 383: 789 -->

<!-- kessler step 96: 443 -->

<!-- kessler step 388: 986 -->

<!-- kessler step 389: 376 -->

<!-- kessler step 103: 989 -->

<!-- kessler step 104: 774 -->

<!-- kessler step 392: 357 -->

<!-- kessler step 398: 278 -->

<!-- kessler step 116: 605 -->

<!-- kessler step 119: 256 -->

<!-- kessler step 407: 624 -->

<!-- kessler step 124: 952 -->

<!-- kessler step 134: 870 -->

<!-- kessler step 420: 391 -->

<!-- kessler step 138: 344 -->

<!-- kessler step 424: 376 -->

<!-- kessler step 426: 416 -->

<!-- kessler step 428: 458 -->

<!-- kessler step 145: 125 -->

<!-- kessler step 429: 693 -->
