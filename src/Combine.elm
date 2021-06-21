module Combine exposing
    ( Parser, InputStream, ParseLocation, ParseContext, ParseResult, ParseError, ParseOk
    , parse, runParser
    , primitive, app, lazy
    , fail, succeed, string, regex, regexSub, regexWith, regexWithSub, end, whitespace, whitespace1
    , map, onsuccess, mapError, onerror
    , andThen, andMap, sequence
    , lookAhead, while, or, choice, optional, maybe, many, many1, manyTill, many1Till, sepBy, sepBy1, sepEndBy, sepEndBy1, skip, skipMany, skipMany1, chainl, chainr, count, between, parens, braces, brackets, keep, ignore
    , withState, putState, modifyState, withLocation, withLine, withColumn, withSourceLine, currentLocation, currentSourceLine, currentLine, currentColumn, currentStream, modifyInput, modifyPosition
    )

{-| This library provides facilities for parsing structured text data
into concrete Elm values.


## API Reference

  - [Core Types](#core-types)
  - [Running Parsers](#running-parsers)
  - [Constructing Parsers](#constructing-parsers)
  - [Parsers](#parsers)
  - [Combinators](#combinators)
      - [Transforming Parsers](#transforming-parsers)
      - [Chaining Parsers](#chaining-parsers)
      - [Parser Combinators](#parser-combinators)
      - [State Combinators](#state-combinators)


## Core Types

@docs Parser, InputStream, ParseLocation, ParseContext, ParseResult, ParseError, ParseOk


## Running Parsers

@docs parse, runParser


## Constructing Parsers

@docs primitive, app, lazy


## Parsers

@docs fail, succeed, string, regex, regexSub, regexWith, regexWithSub, end, whitespace, whitespace1


## Combinators


### Transforming Parsers

@docs map, onsuccess, mapError, onerror


### Chaining Parsers

@docs andThen, andMap, sequence


### Parser Combinators

@docs lookAhead, while, or, choice, optional, maybe, many, many1, manyTill, many1Till, sepBy, sepBy1, sepEndBy, sepEndBy1, skip, skipMany, skipMany1, chainl, chainr, count, between, parens, braces, brackets, keep, ignore


### State Combinators

@docs withState, putState, modifyState, withLocation, withLine, withColumn, withSourceLine, currentLocation, currentSourceLine, currentLine, currentColumn, currentStream, modifyInput, modifyPosition

-}

import Flip exposing (flip)
import Regex
import String


{-| The input stream over which `Parser`s operate.

  - `data` is the initial input provided by the user
  - `input` is the remainder after running a parse
  - `position` is the starting position of `input` in `data` after a parse

-}
type alias InputStream =
    { data : String
    , input : String
    , position : Int
    }


initStream : String -> InputStream
initStream s =
    InputStream s s 0


{-| A record representing the current parse location in an InputStream.

  - `source` the current line of source code
  - `line` the current line number (starting at 1)
  - `column` the current column (starting at 1)

-}
type alias ParseLocation =
    { source : String
    , line : Int
    , column : Int
    }


{-| A tuple representing the current parser state, the remaining input
stream and the parse result. Don't worry about this type unless
you're writing your own `primitive` parsers.
-}
type alias ParseContext state res =
    ( state, InputStream, ParseResult res )


{-| Running a `Parser` results in one of two states:

  - `Ok res` when the parser has successfully parsed the input
  - `Err messages` when the parser has failed with a list of error messages.

-}
type alias ParseResult res =
    Result (List String) res


{-| A tuple representing a failed parse. It contains the state after
running the parser, the remaining input stream and a list of
error messages.
-}
type alias ParseError state =
    ( state, InputStream, List String )


{-| A tuple representing a successful parse. It contains the state
after running the parser, the remaining input stream and the
result.
-}
type alias ParseOk state res =
    ( state, InputStream, res )


type alias ParseFn state res =
    state -> InputStream -> ParseContext state res


{-| The Parser type.

At their core, `Parser`s wrap functions from some `state` and an
`InputStream` to a tuple representing the new `state`, the
remaining `InputStream` and a `ParseResult res`.

-}
type Parser state res
    = Parser (ParseFn state res)



--| RecursiveParser (L.Lazy (ParseFn state res))


{-| Construct a new primitive Parser.

If you find yourself reaching for this function often consider opening
a [Github issue][issues] with the library to have your custom Parsers
included in the standard distribution.

[issues]: https://github.com/elm-community/parser-combinators/issues

-}
primitive : (state -> InputStream -> ParseContext state res) -> Parser state res
primitive =
    Parser


{-| Unwrap a parser so it can be applied to a state and an input
stream. This function is useful if you want to construct your own
parsers via `primitive`. If you're using this outside of the context
of `primitive` then you might be doing something wrong so try asking
for help on the mailing list.

Here's how you would implement a greedy version of `manyTill` using
`primitive` and `app`:

    manyTill : Parser s a -> Parser s x -> Parser s (List a)
    manyTill p end =
        let
            accumulate acc state stream =
                case app end state stream of
                    ( rstate, rstream, Ok _ ) ->
                        ( rstate, rstream, Ok (List.reverse acc) )

                    _ ->
                        case app p state stream of
                            ( rstate, rstream, Ok res ) ->
                                accumulate (res :: acc) rstate rstream

                            ( estate, estream, Err ms ) ->
                                ( estate, estream, Err ms )
        in
        primitive <| accumulate []

-}
app : Parser state res -> state -> InputStream -> ParseContext state res
app (Parser inner) =
    inner


{-| Parse a string. See `runParser` if your parser needs to manage
some internal state.

    import Combine.Num exposing (int)
    import String

    parseAnInteger : String -> Result String Int
    parseAnInteger input =
      case parse int input of
        Ok (_, stream, result) ->
          Ok result

        Err (_, stream, errors) ->
          Err (String.join " or " errors)

    parseAnInteger "123"
    -- Ok 123

    parseAnInteger "abc"
    -- Err "expected an integer"

-}
parse : Parser () res -> String -> Result (ParseError ()) (ParseOk () res)
parse p =
    runParser p ()


{-| Parse a string while maintaining some internal state.

    import Combine.Num exposing (int)
    import String

    type alias Output =
      { count : Int
      , integers : List Int
      }

    statefulInt : Parse Int Int
    statefulInt =
      -- Parse an int, then increment the state and return the parsed
      -- int.  It's important that we try to parse the int _first_
      -- since modifying the state will always succeed.
      int |> ignore (modifyState ((+) 1))

    ints : Parse Int (List Int)
    ints =
      sepBy (string " ") statefulInt

    parseIntegers : String -> Result String Output
    parseIntegers input =
      case runParser ints 0 input of
        Ok (state, stream, ints) ->
          Ok { count = state, integers = ints }

        Err (state, stream, errors) ->
          Err (String.join " or " errors)

    parseIntegers ""
    -- Ok { count = 0, integers = [] }

    parseIntegers "1 2 3 45"
    -- Ok { count = 4, integers = [1, 2, 3, 45] }

    parseIntegers "1 a 2"
    -- Ok { count = 1, integers = [1] }

-}
runParser : Parser state res -> state -> String -> Result (ParseError state) (ParseOk state res)
runParser p st s =
    case app p st (initStream s) of
        ( state, stream, Ok res ) ->
            Ok ( state, stream, res )

        ( state, stream, Err ms ) ->
            Err ( state, stream, ms )


{-| Unfortunatelly this is not a real lazy function anymore, since this
functionality is not accessable anymore by ordinary developers. Use this
function only to avoid "bad-recursion" errors or use the following example
snippet in your code to circumvent this problem:

    recursion x =
        \() -> recursion x

-}
lazy : (() -> Parser s a) -> Parser s a
lazy t =
    --    RecursiveParser (L.lazy (\() -> app (t ())))
    succeed () |> andThen t


{-| Transform both the result and error message of a parser.
-}
bimap :
    (a -> b)
    -> (List String -> List String)
    -> Parser s a
    -> Parser s b
bimap fok ferr p =
    Parser <|
        \state stream ->
            case app p state stream of
                ( rstate, rstream, Ok res ) ->
                    ( rstate, rstream, Ok (fok res) )

                ( estate, estream, Err ms ) ->
                    ( estate, estream, Err (ferr ms) )



-- State management
-- ----------------


{-| Get the parser's state and pipe it into a parser.
-}
withState : (s -> Parser s a) -> Parser s a
withState f =
    Parser <|
        \state stream ->
            app (f state) state stream


{-| Replace the parser's state.
-}
putState : s -> Parser s ()
putState state =
    Parser <|
        \_ stream ->
            app (succeed ()) state stream


{-| Modify the parser's state.
-}
modifyState : (s -> s) -> Parser s ()
modifyState f =
    Parser <|
        \state stream ->
            app (succeed ()) (f state) stream


{-| Get the current position in the input stream and pipe it into a parser.
-}
withLocation : (ParseLocation -> Parser s a) -> Parser s a
withLocation f =
    Parser <|
        \state stream ->
            app (f <| currentLocation stream) state stream


{-| Get the current line and pipe it into a parser.
-}
withLine : (Int -> Parser s a) -> Parser s a
withLine f =
    Parser <|
        \state stream ->
            app (f <| currentLine stream) state stream


{-| Get the current column and pipe it into a parser.
-}
withColumn : (Int -> Parser s a) -> Parser s a
withColumn f =
    Parser <|
        \state stream ->
            app (f <| currentColumn stream) state stream


{-| Get the current InputStream and pipe it into a parser,
only for debugging purposes ...
-}
withSourceLine : (String -> Parser s a) -> Parser s a
withSourceLine f =
    Parser <|
        \state stream ->
            app (f <| currentSourceLine stream) state stream


{-| Get the current `(line, column)` in the input stream.
-}
currentLocation : InputStream -> ParseLocation
currentLocation stream =
    let
        find position currentLine_ lines =
            case lines of
                [] ->
                    ParseLocation "" currentLine_ position

                line :: rest ->
                    let
                        length =
                            String.length line

                        lengthPlusNL =
                            length + 1
                    in
                    if position == length then
                        ParseLocation line currentLine_ position

                    else if position > length then
                        find (position - lengthPlusNL) (currentLine_ + 1) rest

                    else
                        ParseLocation line currentLine_ position
    in
    find stream.position 0 (String.split "\n" stream.data)


{-| Get the current source line in the input stream.
-}
currentSourceLine : InputStream -> String
currentSourceLine =
    currentLocation >> .source


{-| Get the current line in the input stream.
-}
currentLine : InputStream -> Int
currentLine =
    currentLocation >> .line


{-| Get the current column in the input stream.
-}
currentColumn : InputStream -> Int
currentColumn =
    currentLocation >> .column


{-| Get the current string stream. That might be useful for applying memorization.
-}
currentStream : InputStream -> String
currentStream =
    .input


{-| Modify the parser's InputStream input (String).
-}
modifyInput : (String -> String) -> Parser s ()
modifyInput f =
    Parser <|
        \state stream ->
            app (succeed ()) state { stream | input = f stream.input }


{-| Modify the parser's InputStream position (Int).
-}
modifyPosition : (Int -> Int) -> Parser s ()
modifyPosition f =
    Parser <|
        \state stream ->
            app (succeed ()) state { stream | position = f stream.position }



-- Transformers
-- ------------


{-| Transform the result of a parser.

    let
      parser =
        string "a"
          |> map String.toUpper
    in
      parse parser "a"
      -- Ok "A"

-}
map : (a -> b) -> Parser s a -> Parser s b
map f p =
    bimap f identity p


{-| Transform the error of a parser.

    let
      parser =
        string "a"
          |> mapError (always ["bad input"])
    in
      parse parser b
      -- Err ["bad input"]

-}
mapError : (List String -> List String) -> Parser s a -> Parser s a
mapError =
    bimap identity


{-| Sequence two parsers, passing the result of the first parser to a
function that returns the second parser. The value of the second
parser is returned on success.

    import Combine.Num exposing (int)

    choosy : Parser s String
    choosy =
      let
        createParser n =
          if n % 2 == 0 then
            string " is even"
          else
            string " is odd"
      in
        int
          |> andThen createParser

    parse choosy "1 is odd"
    -- Ok " is odd"

    parse choosy "2 is even"
    -- Ok " is even"

    parse choosy "1 is even"
    -- Err ["expected \" is odd\""]

-}
andThen : (a -> Parser s b) -> Parser s a -> Parser s b
andThen f p =
    Parser <|
        \state stream ->
            case app p state stream of
                ( rstate, rstream, Ok res ) ->
                    app (f res) rstate rstream

                ( estate, estream, Err ms ) ->
                    ( estate, estream, Err ms )


{-| Sequence two parsers.

    import Combine.Num exposing (int)

    plus : Parser s String
    plus = string "+"

    sum : Parser s Int
    sum =
      int
        |> map (+)
        |> andMap (plus |> keep int)

    parse sum "1+2"
    -- Ok 3

-}
andMap : Parser s a -> Parser s (a -> b) -> Parser s b
andMap rp lp =
    lp |> andThen (flip map rp)


{-| Run a list of parsers in sequence, accumulating the results. The
main use case for this parser is when you want to combine a list of
parsers into a single, top-level, parser. For most use cases, you'll
want to use one of the other combinators instead.

    parse (sequence [string "a", string "b"]) "ab"
    -- Ok ["a", "b"]

    parse (sequence [string "a", string "b"]) "ac"
    -- Err ["expected \"b\""]

-}
sequence : List (Parser s a) -> Parser s (List a)
sequence parsers =
    let
        accumulate acc ps state stream =
            case ps of
                [] ->
                    ( state, stream, Ok (List.reverse acc) )

                x :: xs ->
                    case app x state stream of
                        ( rstate, rstream, Ok res ) ->
                            accumulate (res :: acc) xs rstate rstream

                        ( estate, estream, Err ms ) ->
                            ( estate, estream, Err ms )
    in
    Parser <|
        \state stream ->
            accumulate [] parsers state stream



-- Combinators
-- -----------


{-| Fail without consuming any input.

    parse (fail "some error") "hello"
    -- Err ["some error"]

-}
fail : String -> Parser s a
fail m =
    Parser <|
        \state stream ->
            ( state, stream, Err [ m ] )


emptyErr : Parser s a
emptyErr =
    Parser <|
        \state stream ->
            ( state, stream, Err [] )


{-| Return a value without consuming any input.

    parse (succeed 1) "a"
    -- Ok 1

-}
succeed : a -> Parser s a
succeed res =
    Parser <|
        \state stream ->
            ( state, stream, Ok res )


{-| Parse an exact string match.

    parse (string "hello") "hello world"
    -- Ok "hello"

    parse (string "hello") "goodbye"
    -- Err ["expected \"hello\""]

-}
string : String -> Parser s String
string s =
    Parser <|
        \state stream ->
            if String.startsWith s stream.input then
                let
                    len =
                        String.length s

                    rem =
                        String.dropLeft len stream.input

                    pos =
                        stream.position + len
                in
                ( state, { stream | input = rem, position = pos }, Ok s )

            else
                ( state, stream, Err [ "expected \"" ++ s ++ "\"" ] )


{-| Parse a Regex match.

Regular expressions must match from the beginning of the input and their
subgroups are ignored. A `^` is added implicitly to the beginning of
every pattern unless one already exists.

    parse (regex "a+") "aaaaab"
    -- Ok "aaaaa"

-}
regex : String -> Parser s String
regex =
    regexer Regex.fromString .match >> Parser


{-| Parse a Regex match.

Same as regex, but returns also submatches as the second parameter in
the result tuple.

    parse (regexSub "a+") "aaaaab"
    -- Ok ("aaaaa", [])

-}
regexSub : String -> Parser s ( String, List (Maybe String) )
regexSub =
    regexer Regex.fromString
        (\m -> ( m.match, m.submatches ))
        >> Parser


{-| Parse a Regex match.

Since, Regex now also has support for more parameters, this option was
included into this package. Call `regexWith` with two additional parameters:
`caseInsensitive` and `multiline`, which allow you to tweak your expression.
The rest is as follows. Regular expressions must match from the beginning
of the input and their subgroups are ignored. A `^` is added implicitly to
the beginning of every pattern unless one already exists.

    parse (regexWith True False "a+") "aaaAAaAab"
    -- Ok "aaaAAaAa"

-}
regexWith : Bool -> Bool -> String -> Parser s String
regexWith caseInsensitive multiline =
    regexer
        (Regex.fromStringWith
            { caseInsensitive = caseInsensitive
            , multiline = multiline
            }
        )
        .match
        >> Parser


{-| Parse a Regex match.

Similar to `regexWith`, but a tuple is returned, with a list of additional
submatches.
The rest is as follows. Regular expressions must match from the beginning
of the input and their subgroups are ignored. A `^` is added implicitly to
the beginning of every pattern unless one already exists.

    parse (regexWithSub True False "a+") "aaaAAaAab"
    -- Ok ("aaaAAaAa", [])

-}
regexWithSub : Bool -> Bool -> String -> Parser s ( String, List (Maybe String) )
regexWithSub caseInsensitive multiline =
    regexer
        (Regex.fromStringWith
            { caseInsensitive = caseInsensitive
            , multiline = multiline
            }
        )
        (\m -> ( m.match, m.submatches ))
        >> Parser


regexer :
    (String -> Maybe Regex.Regex)
    -> (Regex.Match -> res)
    -> String
    -> (state -> InputStream -> ( state, InputStream, ParseResult res ))
regexer input output pat state stream =
    let
        pattern =
            if String.startsWith "^" pat then
                pat

            else
                "^" ++ pat
    in
    case Regex.findAtMost 1 (input pattern |> Maybe.withDefault Regex.never) stream.input of
        [ match ] ->
            let
                len =
                    String.length match.match

                rem =
                    String.dropLeft len stream.input

                pos =
                    stream.position + len
            in
            ( state, { stream | input = rem, position = pos }, Ok (output match) )

        _ ->
            ( state, stream, Err [ "expected input matching Regexp /" ++ pattern ++ "/" ] )


{-| Consume input while the predicate matches.

    parse (while ((/=) ' ')) "test 123"
    -- Ok "test"

-}
while : (Char -> Bool) -> Parser s String
while pred =
    let
        accumulate acc state stream =
            case String.uncons stream.input of
                Just ( h, rest ) ->
                    if pred h then
                        let
                            c =
                                String.cons h ""

                            pos =
                                stream.position + 1
                        in
                        accumulate (acc ++ c) state { stream | input = rest, position = pos }

                    else
                        ( state, stream, acc )

                Nothing ->
                    ( state, stream, acc )
    in
    Parser <|
        \state stream ->
            let
                ( rstate, rstream, res ) =
                    accumulate "" state stream
            in
            ( rstate, rstream, Ok res )


{-| Fail when the input is not empty.

    parse end ""
    -- Ok ()

    parse end "a"
    -- Err ["expected end of input"]

-}
end : Parser s ()
end =
    Parser <|
        \state stream ->
            if stream.input == "" then
                ( state, stream, Ok () )

            else
                ( state, stream, Err [ "expected end of input" ] )


{-| Apply a parser without consuming any input on success.
-}
lookAhead : Parser s a -> Parser s a
lookAhead p =
    Parser <|
        \state stream ->
            case app p state stream of
                ( rstate, _, Ok res ) ->
                    ( rstate, stream, Ok res )

                err ->
                    err


{-| Choose between two parsers.

    parse (or (string "a") (string "b")) "a"
    -- Ok "a"

    parse (or (string "a") (string "b")) "b"
    -- Ok "b"

    parse (or (string "a") (string "b")) "c"
    -- Err ["expected \"a\"", "expected \"b\""]

-}
or : Parser s a -> Parser s a -> Parser s a
or lp rp =
    Parser <|
        \state stream ->
            case app lp state stream of
                ( _, _, Ok _ ) as res ->
                    res

                ( _, _, Err lms ) ->
                    case app rp state stream of
                        ( _, _, Ok _ ) as res ->
                            res

                        ( _, _, Err rms ) ->
                            ( state, stream, Err (lms ++ rms) )


{-| Choose between a list of parsers.

    parse (choice [string "a", string "b"]) "a"
    -- Ok "a"

    parse (choice [string "a", string "b"]) "b"
    -- Ok "b"

-}
choice : List (Parser s a) -> Parser s a
choice xs =
    List.foldr or emptyErr xs


{-| Return a default value when the given parser fails.

    letterA : Parser s String
    letterA = optional "a" (string "a")

    parse letterA "a"
    -- Ok "a"

    parse letterA "b"
    -- Ok "a"

-}
optional : a -> Parser s a -> Parser s a
optional res p =
    succeed res |> or p


{-| Wrap the return value into a `Maybe`. Returns `Nothing` on failure.

    parse (maybe (string "a")) "a"
    -- Ok (Just "a")

    parse (maybe (string "a")) "b"
    -- Ok Nothing

-}
maybe : Parser s a -> Parser s (Maybe a)
maybe p =
    Parser <|
        \state stream ->
            case app p state stream of
                ( rstate, rstream, Ok res ) ->
                    ( rstate, rstream, Ok (Just res) )

                _ ->
                    ( state, stream, Ok Nothing )


{-| Apply a parser zero or more times and return a list of the results.

    parse (many (string "a")) "aaab"
    -- Ok ["a", "a", "a"]

    parse (many (string "a")) "bbbb"
    -- Ok []

    parse (many (string "a")) ""
    -- Ok []

-}
many : Parser s a -> Parser s (List a)
many p =
    let
        accumulate acc state stream =
            case app p state stream of
                ( rstate, rstream, Ok res ) ->
                    if stream == rstream then
                        ( rstate, rstream, List.reverse acc )

                    else
                        accumulate (res :: acc) rstate rstream

                _ ->
                    ( state, stream, List.reverse acc )
    in
    Parser <|
        \state stream ->
            let
                ( rstate, rstream, res ) =
                    accumulate [] state stream
            in
            ( rstate, rstream, Ok res )


{-| Parse at least one result.

    parse (many1 (string "a")) "a"
    -- Ok ["a"]

    parse (many1 (string "a")) ""
    -- Err ["expected \"a\""]

-}
many1 : Parser s a -> Parser s (List a)
many1 p =
    p |> map (::) |> andMap (many p)


{-| Apply the first parser zero or more times until second parser
succeeds. On success, the list of the first parser's results is returned.

    string "<!--" |> keep (manyTill anyChar (string "-->"))

-}
manyTill : Parser s a -> Parser s end -> Parser s (List a)
manyTill p end_ =
    let
        accumulate acc state stream =
            case app end_ state stream of
                ( rstate, rstream, Ok _ ) ->
                    ( rstate, rstream, Ok (List.reverse acc) )

                ( estate, estream, Err ms ) ->
                    case app p state stream of
                        ( rstate, rstream, Ok res ) ->
                            accumulate (res :: acc) rstate rstream

                        _ ->
                            ( estate, estream, Err ms )
    in
    Parser (accumulate [])


{-| Apply the first parser one or more times until second parser
succeeds. On success, the list of the first parser's results is returned.

    string "<!--" |> keep (many1Till anyChar (string "-->"))

-}
many1Till : Parser s a -> Parser s end -> Parser s (List a)
many1Till p =
    manyTill p
        >> andThen
            (\result ->
                case result of
                    [] ->
                        fail "not enough results"

                    _ ->
                        succeed result
            )


{-| Parser zero or more occurences of one parser separated by another.

    parse (sepBy (string ",") (string "a")) "b"
    -- Ok []

    parse (sepBy (string ",") (string "a")) "a,a,a"
    -- Ok ["a", "a", "a"]

    parse (sepBy (string ",") (string "a")) "a,a,b"
    -- Ok ["a", "a"]

-}
sepBy : Parser s x -> Parser s a -> Parser s (List a)
sepBy sep p =
    or (sepBy1 sep p) (succeed [])


{-| Parse one or more occurences of one parser separated by another.
-}
sepBy1 : Parser s x -> Parser s a -> Parser s (List a)
sepBy1 sep p =
    map (::) p |> andMap (many (sep |> keep p))


{-| Parse zero or more occurences of one parser separated and
optionally ended by another.

    parse (sepEndBy (string ",") (string "a")) "a,a,a,"
    -- Ok ["a", "a", "a"]

-}
sepEndBy : Parser s x -> Parser s a -> Parser s (List a)
sepEndBy sep p =
    or (sepEndBy1 sep p) (succeed [])


{-| Parse one or more occurences of one parser separated and
optionally ended by another.

    parse (sepEndBy1 (string ",") (string "a")) ""
    -- Err ["expected \"a\""]

    parse (sepEndBy1 (string ",") (string "a")) "a"
    -- Ok ["a"]

    parse (sepEndBy1 (string ",") (string "a")) "a,"
    -- Ok ["a"]

-}
sepEndBy1 : Parser s x -> Parser s a -> Parser s (List a)
sepEndBy1 sep p =
    sepBy1 sep p |> ignore (maybe sep)


{-| Apply a parser and skip its result.
-}
skip : Parser s x -> Parser s ()
skip p =
    p |> onsuccess ()


{-| Apply a parser and skip its result many times.
-}
skipMany : Parser s x -> Parser s ()
skipMany p =
    many (skip p) |> onsuccess ()


{-| Apply a parser and skip its result at least once.
-}
skipMany1 : Parser s x -> Parser s ()
skipMany1 p =
    many1 (skip p) |> onsuccess ()


{-| Parse one or more occurences of `p` separated by `op`, recursively
apply all functions returned by `op` to the values returned by `p`. See
the `examples/Calc.elm` file for an example.
-}
chainl : Parser s (a -> a -> a) -> Parser s a -> Parser s a
chainl op p =
    let
        accumulate x =
            succeed x
                |> or
                    (op
                        |> andThen
                            (\f ->
                                p
                                    |> andThen (\y -> accumulate (f x y))
                            )
                    )
    in
    andThen accumulate p


{-| Similar to `chainl` but functions of `op` are applied in
right-associative order to the values of `p`. See the
`examples/Python.elm` file for a usage example.
-}
chainr : Parser s (a -> a -> a) -> Parser s a -> Parser s a
chainr op p =
    let
        accumulate x =
            succeed x
                |> or
                    (op
                        |> andThen
                            (\f ->
                                p
                                    |> andThen accumulate
                                    |> andThen (\y -> succeed (f x y))
                            )
                    )
    in
    andThen accumulate p


{-| Parse `n` occurences of `p`.
-}
count : Int -> Parser s a -> Parser s (List a)
count n p =
    let
        accumulate x acc =
            if x <= 0 then
                succeed (List.reverse acc)

            else
                andThen (\res -> accumulate (x - 1) (res :: acc)) p
    in
    accumulate n []


{-| Parse something between two other parsers.

The parser

    between (string "(") (string ")") (string "a")

is equivalent to the parser

    string "(" |> keep (string "a") |> ignore (string ")")

-}
between : Parser s l -> Parser s r -> Parser s a -> Parser s a
between lp rp p =
    lp |> keep p |> ignore rp


{-| Parse something between parentheses.
-}
parens : Parser s a -> Parser s a
parens =
    between (string "(") (string ")")


{-| Parse something between braces `{}`.
-}
braces : Parser s a -> Parser s a
braces =
    between (string "{") (string "}")


{-| Parse something between square brackets `[]`.
-}
brackets : Parser s a -> Parser s a
brackets =
    between (string "[") (string "]")


{-| Parse zero or more whitespace characters.

    parse (whitespace |> keep (string "hello")) "hello"
    -- Ok "hello"

    parse (whitespace |> keep (string "hello")) "   hello"
    -- Ok "hello"

-}
whitespace : Parser s String
whitespace =
    regex "\\s*" |> onerror "optional whitespace"


{-| Parse one or more whitespace characters.

    parse (whitespace1 |> keep (string "hello")) "hello"
     -- Err ["whitespace"]

    parse (whitespace1 |> keep (string "hello")) "   hello"
     -- Ok "hello"

-}
whitespace1 : Parser s String
whitespace1 =
    regex "\\s+" |> onerror "whitespace"


{-| Variant of `mapError` that replaces the Parser's error with a List
of a single string.

    parse (string "a" |> onerror "gimme an 'a'") "b"
    -- Err ["gimme an 'a'"]

-}
onerror : String -> Parser s a -> Parser s a
onerror m p =
    mapError (always [ m ]) p


{-| Run a parser and return the value on the right on success.

    parse (string "true" |> onsuccess True) "true"
    -- Ok True

    parse (string "true" |> onsuccess True) "false"
    -- Err ["expected \"true\""]

-}
onsuccess : a -> Parser s x -> Parser s a
onsuccess res =
    map (always res)


{-| Join two parsers, ignoring the result of the one on the right.

    unsuffix : Parser s String
    unsuffix =
      regex "[a-z]"
        |> keep (regex "[!?]")

    parse unsuffix "a!"
    -- Ok "a"

-}
keep : Parser s a -> Parser s x -> Parser s a
keep p1 p2 =
    p2
        |> map (flip always)
        |> andMap p1


{-| Join two parsers, ignoring the result of the one on the left.

    unprefix : Parser s String
    unprefix =
      string ">"
        |> ignore (while ((==) ' '))
        |> ignore (while ((/=) ' '))

    parse unprefix "> a"
    -- Ok "a"

-}
ignore : Parser s x -> Parser s a -> Parser s a
ignore p1 p2 =
    p2
        |> map always
        |> andMap p1
