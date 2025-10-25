# Digital Ping-Pong Game (FPGA-Based)

> Project Date: Spring 2023

This project is a two-player digital ping-pong game designed from the ground up and implemented on an FPGA using Verilog. The system uses switch-based user inputs to control the paddles and provides real-time game feedback through on-board LEDs and a 7-segment display scoreboard.

## 1. Key Features

* **FPGA Game Implementation:** Designed and implemented a complete two-player ping-pong game on an FPGA.
* **FSM-Based Game Logic:** Developed a finite state machine (FSM) in Verilog to manage all game states, user inputs, and display feedback.
* **Real-Time Scoreboard:** Developed a real-time scoreboard using 7-segment displays.
* **Combinational Logic Optimization:** Applied Karnaugh map (K-Map) analysis to design and optimize the combinational logic required for the 7-segment display driver.

## 2. Technical Details

### Game Logic
The core of the game is a Finite State Machine (FSM) that manages the game's progression. It handles inputs from the players' switches, updates the ball's position, detects collisions, and manages point scoring.

### Scoreboard
A real-time scoreboard was developed to display the score. The logic for the 7-segment display driver was manually designed and optimized using K-Map analysis to efficiently convert the binary score count into the correct display signals.

## 3. Tech Stack

* **Hardware:** FPGA, Switches, LEDs, 7-Segment Displays
* **Language:** Verilog
* **Tools:** ModelSim (or other Verilog simulator)
* **Core Concepts:**
    * Finite State Machines (FSM)
    * Digital Logic Design
    * Combinational Logic Optimization
    * Karnaugh Maps (K-Map)
