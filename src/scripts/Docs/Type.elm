module Docs.Type exposing (..)

import Char
import Dict exposing (Dict)
import Html exposing (..)
import String
import Docs.Name as Name exposing (Name)
import Utils.Code as Code exposing (arrow, colon, padded, space)


type Type
    = Function (List Type) Type
    | Var String
    | Apply Name (List Type)
    | Tuple (List Type)
    | Record (List ( String, Type )) (Maybe String)


type Context
    = Func
    | App
    | Other


toHtml : Context -> Type -> List (Html msg)
toHtml context tipe =
    case tipe of
        Function args result ->
            let
                maybeAddParens =
                    case context of
                        Func ->
                            Code.addParens

                        App ->
                            Code.addParens

                        Other ->
                            identity

                argsHtml =
                    List.concatMap (\arg -> toHtml Func arg ++ padded arrow) args
            in
                maybeAddParens (argsHtml ++ toHtml Func result)

        Var name ->
            [ text name ]

        Apply name [] ->
            [ text (name.name) ]

        Apply name args ->
            let
                maybeAddParens =
                    case context of
                        Func ->
                            identity

                        App ->
                            Code.addParens

                        Other ->
                            identity

                argsHtml =
                    List.concatMap (\arg -> space :: toHtml App arg) args
            in
                maybeAddParens (text (name.name) :: argsHtml)

        Tuple args ->
            List.map (toHtml Other) args
                |> List.intersperse [ text ", " ]
                |> List.concat
                |> Code.addParens

        Record fields ext ->
            let
                fieldsHtml =
                    List.map fieldToHtml fields
                        |> List.intersperse [ text ", " ]
                        |> List.concat

                recordInsides =
                    case ext of
                        Nothing ->
                            fieldsHtml

                        Just extName ->
                            text extName :: text " | " :: fieldsHtml
            in
                text "{ " :: recordInsides ++ [ text " }" ]


fieldToHtml : ( String, Type ) -> List (Html msg)
fieldToHtml ( field, tipe ) =
    text field :: space :: colon :: space :: toHtml Other tipe


length : Context -> Type -> Int
length context tipe =
    case tipe of
        Function args result ->
            let
                parens =
                    case context of
                        Func ->
                            2

                        App ->
                            2

                        Other ->
                            0

                argLengths =
                    List.map (\t -> 4 + length Func t) args
            in
                parens + List.sum argLengths + length Func result

        Var name ->
            String.length name

        Apply { name } [] ->
            String.length name

        Apply { name } args ->
            let
                parens =
                    case context of
                        Func ->
                            0

                        App ->
                            2

                        Other ->
                            0

                argsLength =
                    List.sum (List.map (\t -> 1 + length App t) args)
            in
                parens + String.length name + argsLength

        Tuple args ->
            List.sum (List.map (\t -> 2 + length Other t) args)

        Record fields ext ->
            let
                fieldLength ( field, tipe ) =
                    String.length field + 3 + length Other tipe

                recordLength =
                    2 + List.sum (List.map (\ft -> 2 + fieldLength ft) fields)

                extLength =
                    case ext of
                        Nothing ->
                            0

                        Just extName ->
                            2 + String.length extName
            in
                recordLength + extLength



-- NORMALIZE


reserverdVars : Dict String (List String)
reserverdVars =
    Dict.empty
        |> Dict.insert "number" [ "Float", "Int" ]
        |> Dict.insert "comparable" [ "Float", "Int", "Char", "String" ]
        |> Dict.insert "appendable" [ "String", "List" ]


type alias Mapping =
    Dict String String


defaultMapping : Mapping
defaultMapping =
    Dict.keys reserverdVars
        |> List.map (\v -> ( v, v ))
        |> Dict.fromList


nextMappingValue : Mapping -> String
nextMappingValue mapping =
    let
        base =
            (Dict.size mapping) - (Dict.size defaultMapping)

        code =
            (base % 26) + (Char.toCode 'a')

        string =
            String.fromChar (Char.fromCode code)

        times =
            (base // 26) + 1
    in
        String.repeat times string


updateMapping : Type -> Mapping -> Mapping
updateMapping tipe mapping =
    let
        updateMappingFor name =
            if Dict.member name mapping then
                mapping
            else
                Dict.insert name
                    (nextMappingValue mapping)
                    mapping
    in
        case tipe of
            Function args result ->
                List.foldl updateMapping mapping (List.append args [ result ])

            Var name ->
                updateMappingFor name

            Apply name args ->
                List.foldl updateMapping mapping args

            Tuple args ->
                List.foldl updateMapping mapping args

            Record fields ext ->
                List.foldl updateMapping mapping (List.map (\( _, t ) -> t) fields)


normalize : Type -> Type
normalize tipe =
    normalizeWithMapping (updateMapping tipe defaultMapping) tipe


normalizeWithMapping : Mapping -> Type -> Type
normalizeWithMapping mapping tipe =
    let
        normalize' =
            normalizeWithMapping mapping
    in
        case tipe of
            Function args result ->
                Function (List.map normalize' args)
                    (normalize' result)

            Var name ->
                let
                    name' =
                        case Dict.get name mapping of
                            Just n ->
                                n

                            Nothing ->
                                name
                in
                    Var name'

            Apply name args ->
                Apply name (List.map normalize' args)

            Tuple args ->
                Tuple (List.map normalize' args)

            Record fields ext ->
                Record (List.map (\( k, v ) -> ( k, normalize' v )) fields) ext
