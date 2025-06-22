# GameRank Godot library using the HTTPs REST API.
# Version 0.1 - 2024-11
extends Node

# Score contain one score of one player. Used to return the top list of scores
# of the leaderboard.
class Score:
    var userid: String
    var username: String
    var score: int
    var date: int # UTC timestamp in millisecond

    func _init(userid: String, username: String, score: int, date: int):
        self.userid = userid
        self.username = username
        self.score = score
        self.date = date

# PersonalBest contains information on a personal best score of a player.
class PersonalBest:
    var score: int
    var position: int
    var is_new_best: bool

    func _init(score: int, position: int, is_new_best: bool):
        self.score = score
        self.position = position
        self.is_new_best = is_new_best

const GAMERANK_NO_ERROR = 0 # Error code returned when no error happened.
const GAMERANK_ERROR_CONNECTION = 1 # Error code on a connection error.
const GAMERANK_ERROR_INVALID_RESPONSE = 2 # Error code on an invalid response from GameRank servers.

# Main class containing all functions to use GameRank features
# through the HTTPs REST API.
class HighscoresLeaderboard:
    var apikey: String = ""
    var tree: SceneTree

    # Constructor
    # Parameters:
    #   - apikey (string): the GameRank API key of the leaderboard to use.
    func _init(tree: SceneTree, apikey: String):
        self.tree = tree
        self.apikey = apikey

    # Send a new player score.
    # Parameters:
    #   - userid   (string)                  : unique identifier of the player
    #   - username (string)                  : player's username
    #   - score    (int)                     : player's new score to submit
    #   - callback (func(PersonalBest, int)) : callback executed when the score has been processed
    #                                          or if an error happened.
    #                                          First parameter of the callback is the player PersonalBest.
    #                                          Second parameter is an error code if any
    #                                          error occurred, or GAMERANK_NO_ERROR.
    func send_score(userid: String, username: String, score: int, callback: Callable):
        # http client
        var http_client = await self._build_http_client()
        if http_client == null:
            print("GameRank: Error while building the HTTP client")
            callback.call(null, GAMERANK_ERROR_CONNECTION)
            return

        # prepare and send the request
        var request_object = {
            "userid": self.sanitize_userid(userid),
            "username": username,
            "score": score,
            "return_best": true,
        }
        var err = http_client.request_raw(HTTPClient.METHOD_POST,
                                        "/scoreboard/submit",
                                        self._build_http_headers(),
                                        JSON.stringify(request_object).to_utf8_buffer())

        # wait for the response
        if err != OK:
            print("GameRank: Error while running request_raw: " + str(err))
            callback.call(null, GAMERANK_ERROR_CONNECTION)
            return
        while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
            http_client.poll()
            await self.tree.process_frame

        # read the body
        if !http_client.has_response():
            callback.call(null, GAMERANK_ERROR_INVALID_RESPONSE)
            return
        var json = await _body_to_json(http_client)
        if json == null:
            callback.call(null, GAMERANK_ERROR_INVALID_RESPONSE)
            return

        var response_object = Dictionary(json.data)
        callback.call(PersonalBest.new(
                        int(response_object["best"]),
                        int(response_object["best_position"]),
                        bool(response_object["is_new_best"])),
                      GAMERANK_NO_ERROR)

    # Returns the top scores of the leaderboard
    # Parameters:
    #   - count    (int)                     : how many top scores to return.
    #   - callback (func(Array[Score], int)) : callback executed when the list of scores is
    #                                          ready or if an error happened.
    #                                          The first parameter is the Array of Score.
    #                                          Second parameter is an error code if any
    #                                          error occurred, or GAMERANK_NO_ERROR.
    func get_top_scores(count: int, callback: Callable):
        var rv: Array[Score]

        # http client
        var http_client = await self._build_http_client()
        if http_client == null:
            print("GameRank: Error while building the HTTP client")
            callback.call(rv, GAMERANK_ERROR_CONNECTION)
            return

        # prepare and send the request
        var err = http_client.request_raw(HTTPClient.METHOD_GET,
                                        "/scoreboard/top/" + str(count),
                                        self._build_http_headers(), PackedByteArray())

        # wait for the response
        if err != OK:
            print("GameRank: Error while running request_raw: " + str(err))
            callback.call(rv, GAMERANK_ERROR_CONNECTION)
            return
        while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
            http_client.poll()
            await self.tree.process_frame

        # read the body
        if !http_client.has_response():
            callback.call(rv, GAMERANK_ERROR_INVALID_RESPONSE)
            return
        var json = await _body_to_json(http_client)
        if json == null || json.data == null:
            callback.call(rv, GAMERANK_ERROR_INVALID_RESPONSE)
            return

        # interpret the response
        var response_object = Array(json.data)
        for entry in response_object:
            var obj = Dictionary(entry)
            var score = Score.new(obj["userid"], obj["username"],
                                  int(obj["entry"]), int(obj["creation_time"]))
            rv.append(score)

        callback.call(rv, GAMERANK_NO_ERROR)

    func sanitize_userid(username: String):
        var rv = ""
        for c in username:
            if (c > 'a' && c < 'z') || (c > 'A' && c < 'Z') || (c > '0' && c < '9'):
                rv += c
        return rv

    # private method
    func _body_to_json(http_client):
        var buff = PackedByteArray() # Array that will hold the data.
        while http_client.get_status() == HTTPClient.STATUS_BODY:
            http_client.poll()
            var chunk = http_client.read_response_body_chunk()
            if chunk.size() == 0:
                await self.tree.process_frame
            else:
                buff = buff + chunk # Append to read buffer.
        var json = JSON.new()
        var parse_err = json.parse(buff.get_string_from_utf8())
        if parse_err != OK:
            print("GameRank: can't parse JSON response: ", parse_err)
            return null
        return json


    # private method
    func _build_http_client():
        var http_client = HTTPClient.new()
        http_client.connect_to_host("https://api.gamerank.io", 443)
        http_client.blocking_mode_enabled = true
        while http_client.get_status() == HTTPClient.STATUS_CONNECTING or http_client.get_status() == HTTPClient.STATUS_RESOLVING:
            http_client.poll()
            await self.tree.process_frame

        if (http_client.get_status() != HTTPClient.STATUS_CONNECTED):
            return null
        return http_client

    # private method
    func _build_http_headers():
        return PackedStringArray(["x-gr-apikey: " + self.apikey])
