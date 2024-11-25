extends Control

# The three lines below is what you will have to include in your game:
# they create the GameRank class instance implementing all GameRank features
# through the HTTPs REST API.
# From here, you can check how is this class instance used in game.gd to see
# how you can use the GameRank class, but make sure to also open the gamerank.gd
# file to see all available functions.
# Please visit https://gamerank.io for more information.
const GAMERANK_APIKEY = "your_leaderboard_apikey"
const GameRank = preload("res://gamerank.gd")
@onready var Leaderboard = GameRank.HighscoresLeaderboard.new(self.get_tree(), GAMERANK_APIKEY)

# Below is the basic game implementation.
class GameInstance:
    var started: bool = false
    var random_running: bool = false
    var random: int = 0
    var username: String = ""
    func reset():
        started = false
        random_running = false
        username = ""
        random = 0
    func start():
        started = true
        random_running = true
    func stop_random():
        random_running = false

var instance = GameInstance.new()

func _ready():
    $NewGamePanel/StartNewGameButton.pressed.connect(self._on_new_game_pressed)
    $RestartButton.pressed.connect(self._on_restart_pressed)
    $ViewLeaderboardButton.pressed.connect(self._on_view_leaderboard_pressed)
    $NewGamePanel/Username.text_changed.connect(self._on_username_text_changed)
    $GamePanel/StopButton.pressed.connect(self._on_stop_button_pressed)
    $GamePanel/SubmitScoreButton.pressed.connect(self._on_submit_score_pressed)
    $QuitButton.pressed.connect(self._on_quit_pressed)
    $NewGamePanel/StartNewGameButton.grab_focus()
    restart()

func _process(delta):
    if instance.started and instance.random_running:
        instance.random = 100+(randi()%12000)
        $GamePanel/Label.text = str(instance.random)

func _on_restart_pressed():
    restart()

func _on_new_game_pressed():
    if instance.username.length() == 0:
        return
    $NewGamePanel.hide()
    $CongratsPanel.hide()
    $CongratsPanel/Score.text = "Sending your score..."
    $GamePanel.show()
    instance.start()

func _on_stop_button_pressed():
    if instance.random_running == false:
        $GamePanel/StopButton.text = "STOP!"
        $GamePanel/SubmitScoreButton.disabled = true
        instance.random_running = true
    else:
        $GamePanel/StopButton.text = "Reroll!"
        $GamePanel/SubmitScoreButton.disabled = false
        instance.random_running = false

func _on_username_text_changed(text: String):
    if (text.length() > 0):
        instance.username = text
        $NewGamePanel/StartNewGameButton.disabled = false
    else:
        instance.username = ""
        $NewGamePanel/StartNewGameButton.disabled = true

func _on_view_leaderboard_pressed():
    $ViewLeaderboardButton.disabled = true
    $GamePanel.hide()
    $NewGamePanel.hide()
    $CongratsPanel.hide()
    $LeaderboardPanel.show()
    $LeaderboardPanel/LoadingLabel.show()
    $LeaderboardPanel/LoadingLabel.text = "Loading..."
    Leaderboard.get_top_scores(50, _on_top_scores_received)

func _on_top_scores_received(scores: Array[GameRank.Score], error_code: int):
    $LeaderboardPanel/Leaderboard.clear()

    if error_code > 0:
        $LeaderboardPanel/LoadingLabel.text = "An error happened."
        return

    $LeaderboardPanel/LoadingLabel.hide()
    var i = 1
    for score in scores:
        var you = ""
        if score.username == instance.username:
            you = "(YOU!)"
        $LeaderboardPanel/Leaderboard.add_item(str(i) + ". " + str(score.score) + " - " + score.username + " " + you, null, false)
        i += 1

func _on_submit_score_pressed():
    $GamePanel.hide()
    $NewGamePanel.hide()
    $CongratsPanel.hide()
    $LeaderboardPanel.hide()

    Leaderboard.send_score(instance.username, instance.username, instance.random, _on_score_sent)

    $CongratsPanel.show()

func restart():
    instance.reset()
    $NewGamePanel/Username.text = ""
    $NewGamePanel.show()
    $GamePanel/SubmitScoreButton.disabled = true
    $GamePanel/StopButton.text = "STOP!"
    $GamePanel.hide()
    $LeaderboardPanel.hide()
    $CongratsPanel.hide()
    $ViewLeaderboardButton.disabled = false

func _on_score_sent(position: GameRank.PersonalBest, error_code: int):
    if error_code > 0:
        $CongratsPanel/Message.text = "An error happened."
        $CongratsPanel/Score.hide()
        return

    $CongratsPanel/Username.text = instance.username + ", with " + str(instance.random) + " you are #" + str(position.position) + "\nin the leaderboard"
    $CongratsPanel/Score.text = "Your best score is " + str(position.score)
    if instance.random >= position.score:
        instance.random = position.score
        $CongratsPanel/Message.text = "YOUR NEW BEST SCORE!"
    else:
        $CongratsPanel/Message.text = "But it's not your new best score."

# Quit the game
func _on_quit_pressed():
    get_tree().quit()
