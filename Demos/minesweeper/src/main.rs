//! Minesweeper, powered by the Swift Win95 library over C FFI.
//! Game logic lives here; all drawing is Swift/AppKit.

use std::ffi::CString;
use std::os::raw::c_void;
use std::ptr::{addr_of, addr_of_mut};
use std::time::{Duration, Instant};

type CellCB = extern "C" fn(*mut c_void, i32, i32, i32);
type ActionCB = extern "C" fn(*mut c_void);

extern "C" {
    fn w95_init();
    fn w95_run();
    fn w95_window_new(title: *const i8, x: f64, y: f64, w: f64, h: f64) -> *mut c_void;
    fn w95_window_set_status(win: *mut c_void, text: *const i8);
    fn w95_install_menus(app_name: *const i8);
    fn w95_board_new(win: *mut c_void, cols: i32, rows: i32,
                     cell_cb: CellCB, face_cb: ActionCB, ud: *mut c_void) -> *mut c_void;
    fn w95_board_set_cell(board: *mut c_void, x: i32, y: i32, state: i32);
    fn w95_board_set_number(board: *mut c_void, x: i32, y: i32, n: i32);
    fn w95_board_set_face(board: *mut c_void, face: i32);
    fn w95_board_set_counters(board: *mut c_void, left: i32, right: i32);
    fn w95_dispatch_main(cb: ActionCB, ud: *mut c_void);
}

const COLS: usize = 9;
const ROWS: usize = 9;
const MINES: usize = 10;

// cell states matching W95BoardView.Cell
const HIDDEN: i32 = 0;
const REVEALED: i32 = 1;
const FLAG: i32 = 2;
const MINE: i32 = 3;
const EXPLODED: i32 = 4;
const WRONG_FLAG: i32 = 5;

// faces
const SMILE: i32 = 0;
const DEAD: i32 = 1;
const COOL: i32 = 2;

#[derive(Clone, Copy, PartialEq)]
enum Cell { Hidden, Revealed, Flag }

struct Game {
    mines: [[bool; COLS]; ROWS],
    cells: [[Cell; COLS]; ROWS],
    counts: [[u8; COLS]; ROWS],
    started: bool,
    over: bool,
    won: bool,
    flags: i32,
    revealed: i32,
    start_time: Option<Instant>,
    board: *mut c_void,
}

// xorshift — no crates needed
struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13; x ^= x >> 7; x ^= x << 17;
        self.0 = x; x
    }
    fn below(&mut self, n: usize) -> usize { (self.next() % n as u64) as usize }
}

impl Game {
    fn new() -> Self {
        Game {
            mines: [[false; COLS]; ROWS],
            cells: [[Cell::Hidden; COLS]; ROWS],
            counts: [[0; COLS]; ROWS],
            started: false, over: false, won: false,
            flags: 0, revealed: 0, start_time: None,
            board: std::ptr::null_mut(),
        }
    }

    fn place_mines(&mut self, safe_x: usize, safe_y: usize) {
        let seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos() as u64;
        let mut rng = Rng(seed | 1);
        let mut placed = 0;
        while placed < MINES {
            let x = rng.below(COLS);
            let y = rng.below(ROWS);
            if self.mines[y][x] || (x == safe_x && y == safe_y) { continue; }
            self.mines[y][x] = true;
            placed += 1;
        }
        for y in 0..ROWS {
            for x in 0..COLS {
                let mut n = 0;
                for dy in -1i32..=1 { for dx in -1i32..=1 {
                    let nx = x as i32 + dx; let ny = y as i32 + dy;
                    if nx >= 0 && ny >= 0 && nx < COLS as i32 && ny < ROWS as i32
                        && self.mines[ny as usize][nx as usize] { n += 1; }
                }}
                self.counts[y][x] = n;
            }
        }
    }

    fn reveal(&mut self, x: usize, y: usize) {
        if self.cells[y][x] != Cell::Hidden { return; }
        self.cells[y][x] = Cell::Revealed;
        self.revealed += 1;
        unsafe {
            w95_board_set_cell(self.board, x as i32, y as i32, REVEALED);
            w95_board_set_number(self.board, x as i32, y as i32, self.counts[y][x] as i32);
        }
        if self.counts[y][x] == 0 && !self.mines[y][x] {
            for dy in -1i32..=1 { for dx in -1i32..=1 {
                let nx = x as i32 + dx; let ny = y as i32 + dy;
                if nx >= 0 && ny >= 0 && nx < COLS as i32 && ny < ROWS as i32 {
                    self.reveal(nx as usize, ny as usize);
                }
            }}
        }
    }

    fn click(&mut self, x: usize, y: usize) {
        if self.over { return; }
        if !self.started {
            self.place_mines(x, y);
            self.started = true;
            self.start_time = Some(Instant::now());
        }
        if self.cells[y][x] != Cell::Hidden { return; }
        if self.mines[y][x] {
            self.boom(x, y);
            return;
        }
        self.reveal(x, y);
        if self.revealed == (COLS * ROWS - MINES) as i32 {
            self.won = true; self.over = true;
            unsafe { w95_board_set_face(self.board, COOL); }
            self.status("You win. The year is yours.");
        }
    }

    fn flag(&mut self, x: usize, y: usize) {
        if self.over { return; }
        match self.cells[y][x] {
            Cell::Hidden => {
                self.cells[y][x] = Cell::Flag; self.flags += 1;
                unsafe { w95_board_set_cell(self.board, x as i32, y as i32, FLAG); }
            }
            Cell::Flag => {
                self.cells[y][x] = Cell::Hidden; self.flags -= 1;
                unsafe { w95_board_set_cell(self.board, x as i32, y as i32, HIDDEN); }
            }
            _ => {}
        }
        self.update_counters();
    }

    fn boom(&mut self, x: usize, y: usize) {
        self.over = true;
        for yy in 0..ROWS { for xx in 0..COLS {
            let state = if xx == x && yy == y { EXPLODED }
                else if self.mines[yy][xx] && self.cells[yy][xx] != Cell::Flag { MINE }
                else if !self.mines[yy][xx] && self.cells[yy][xx] == Cell::Flag { WRONG_FLAG }
                else { continue };
            unsafe { w95_board_set_cell(self.board, xx as i32, yy as i32, state); }
        }}
        unsafe { w95_board_set_face(self.board, DEAD); }
        self.status("Boom. Press the face to try again.");
    }

    fn reset(&mut self) {
        *self = Game::new();
        // board pointer survives reset
        self.board = unsafe { addr_of!(BOARD).read() };
        for y in 0..ROWS { for x in 0..COLS {
            unsafe {
                w95_board_set_cell(self.board, x as i32, y as i32, HIDDEN);
                w95_board_set_number(self.board, x as i32, y as i32, 0);
            }
        }}
        unsafe {
            w95_board_set_face(self.board, SMILE);
        }
        self.update_counters();
        self.status("Ready");
    }

    fn elapsed(&self) -> i32 {
        self.start_time.map(|t| t.elapsed().as_secs() as i32).unwrap_or(0)
    }

    fn update_counters(&self) {
        unsafe {
            w95_board_set_counters(self.board, MINES as i32 - self.flags, self.elapsed());
        }
    }

    fn status(&self, s: &str) {
        let c = CString::new(s).unwrap();
        unsafe { w95_window_set_status(addr_of!(WIN).read(), c.as_ptr()); }
    }
}

static mut GAME: Option<Game> = None;
static mut BOARD: *mut c_void = std::ptr::null_mut();
static mut WIN: *mut c_void = std::ptr::null_mut();

extern "C" fn on_cell(_ud: *mut c_void, x: i32, y: i32, button: i32) {
    // Swift only sends in-range coords, but these arrive over FFI — never
    // trust them into an array index (`as usize` would wrap negatives).
    if x < 0 || y < 0 || x >= COLS as i32 || y >= ROWS as i32 { return; }
    let g = unsafe { (*addr_of_mut!(GAME)).as_mut().unwrap() };
    let was_over = g.over;
    match button {
        0 => g.click(x as usize, y as usize),
        _ => g.flag(x as usize, y as usize),
    }
    // Once the game is over the clock is frozen: tick() already stops
    // refreshing it, so don't let stray post-game clicks advance it either.
    // (The finally-winning/losing click still updates: was_over is false.)
    if !was_over { g.update_counters(); }
}

extern "C" fn on_face(_ud: *mut c_void) {
    unsafe { (*addr_of_mut!(GAME)).as_mut().unwrap() }.reset();
}

// timer tick: hop to main thread, update the clock counter
extern "C" fn tick(_ud: *mut c_void) {
    let g = unsafe { (*addr_of_mut!(GAME)).as_mut().unwrap() };
    if g.started && !g.over { g.update_counters(); }
}

fn main() {
    unsafe {
        w95_init();
        w95_install_menus(CString::new("Minesweeper").unwrap().as_ptr());
        addr_of_mut!(GAME).write(Some(Game::new()));

        // window sized to the board: 9*16 + padding + chrome
        let title = CString::new("Minesweeper").unwrap();
        addr_of_mut!(WIN).write(w95_window_new(title.as_ptr(), 500.0, 300.0, 180.0, 280.0));

        addr_of_mut!(BOARD).write(w95_board_new(addr_of!(WIN).read(), COLS as i32, ROWS as i32, on_cell, on_face, std::ptr::null_mut()));
        let g = (*addr_of_mut!(GAME)).as_mut().unwrap();
        g.board = addr_of!(BOARD).read();
        g.update_counters();
        g.status("Ready");
        // clock thread → dispatch to main
        std::thread::spawn(|| loop {
            std::thread::sleep(Duration::from_millis(500));
            w95_dispatch_main(tick, std::ptr::null_mut());
        });

        w95_run();
    }
}
