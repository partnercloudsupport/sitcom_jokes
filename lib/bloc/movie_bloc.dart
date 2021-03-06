import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:rxdart/rxdart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sitcom_joke_app/models/ImageJoke.dart';
import 'package:sitcom_joke_app/models/Joke.dart';
import 'package:sitcom_joke_app/models/TextJoke.dart';
import 'package:sitcom_joke_app/models/bloc_completer.dart';
import 'package:sitcom_joke_app/models/joke_type.dart';
import 'package:sitcom_joke_app/models/load_status.dart';
import 'package:sitcom_joke_app/models/movie.dart';
import 'package:sitcom_joke_app/models/user.dart';
import 'package:sitcom_joke_app/utils/date_formatter.dart';

class MovieBloc {
  List<Movie> _movies = [];
  Map<String, Movie> movieCache = {};

  List<ImageJoke> _imageJokes = [];
  List<TextJoke> _textJokes = [];

  DocumentSnapshot _lastImageJoke;
  DocumentSnapshot _lastTextJoke;

  int _currentImagePage = 1;
  int _currentTextPage = 1;

  final _moviesSubject = BehaviorSubject<UnmodifiableListView<Movie>>(
      seedValue: UnmodifiableListView([]));
  final _getMoviesSubject = BehaviorSubject<Map>(seedValue: null);
  final _movieLoadStatusSubject =
      BehaviorSubject<LoadStatus>(seedValue: LoadStatus.loading);
  final _imageJokesSubject = BehaviorSubject<UnmodifiableListView<ImageJoke>>(
      seedValue: UnmodifiableListView([]));
  final _textJokesSubject = BehaviorSubject<UnmodifiableListView<TextJoke>>(
      seedValue: UnmodifiableListView([]));
  final _getJokesSubject = BehaviorSubject<Map>(seedValue: null);
  final _imageLoadStatusSubject =
      BehaviorSubject<LoadStatus>(seedValue: LoadStatus.loading);
  final _textLoadStatusSubject =
      BehaviorSubject<LoadStatus>(seedValue: LoadStatus.loading);
  final _selectedMovieSubject = BehaviorSubject<Movie>(seedValue: Movie(id: null));
  final _searchedMovieResultSubject =
      BehaviorSubject<UnmodifiableListView<Movie>>(
          seedValue: UnmodifiableListView([]));
  final _movieTermToSearchSubject = BehaviorSubject<String>(seedValue: null);

  final _uploadJokeSubject = BehaviorSubject<Map>(seedValue: null);
  final _uploadLoadStatusSubject =
      BehaviorSubject<LoadStatus>(seedValue: LoadStatus.loadEnd);
  final _toggleFavoriteSubject = BehaviorSubject<Map>(seedValue: null);
  final _getFavSubject = BehaviorSubject<bool>(seedValue: false);

  Stream<UnmodifiableListView<Movie>> get movies => _moviesSubject.stream;
  Stream<LoadStatus> get movieLoadStatus => _movieLoadStatusSubject.stream;
  Stream<UnmodifiableListView<ImageJoke>> get imageJokes =>
      _imageJokesSubject.stream;
  Stream<UnmodifiableListView<TextJoke>> get textJokes =>
      _textJokesSubject.stream;
  Stream<LoadStatus> get imageLoadStatus => _imageLoadStatusSubject.stream;
  Stream<LoadStatus> get textLoadStatus => _textLoadStatusSubject.stream;
  Stream<Movie> get selectedMovie => _selectedMovieSubject.stream;
  Stream<UnmodifiableListView<Movie>> get searchedMovieResult =>
      _searchedMovieResultSubject.stream;
  Stream<LoadStatus> get uploadLoadStatus => _uploadLoadStatusSubject.stream;

  //sink
  Function(String) get getMoviesLike =>
      (searchTerm) => _movieTermToSearchSubject.sink.add(searchTerm);
  void Function(JokeType, User) get getJokes =>
      (jokeType, currentUser) => _getJokesSubject.sink.add({'jokeType': jokeType, 'currentUser': currentUser});

  Function(String, JokeType, User) get toggleFavorite => (jokeId, jokeType, currentUser) => _toggleFavoriteSubject.sink.add({'jokeId': jokeId, 'jokeType': jokeType, 'currentUser':currentUser});

  Function(Movie) get changeSelectedMovie => (movie) {
        _currentImagePage = 1; //TODO: put all this in the options observer if all options share it
        _currentTextPage = 1;
        _lastImageJoke = null;
        _lastTextJoke = null;
        return _selectedMovieSubject.sink.add(movie);
      };

  Function(bool) get getFav => (getFav){
        
        _currentImagePage = 1;
        _currentTextPage = 1;
        _lastImageJoke = null;
        _lastTextJoke = null;
        return _getFavSubject.sink.add(getFav);
  };

  Function() get getMovies => () => _getMoviesSubject.sink.add(null);
  Function(Joke, File, BlocCompleter) get upLoadJoke => (joke, image , completer) =>
      _uploadJokeSubject.sink.add({'joke': joke, 'image': image, 'completer': completer});

  MovieBloc() {

    _toggleFavoriteSubject.stream.listen((options) async {

          String jokeId = options['jokeId'];
          JokeType jokeType = options['jokeType'];
          User currentUser = options['currentUser'];

          String jokeFavName;
          bool removeJoke;
          int jokeIndex;

      

          if(jokeType == JokeType.text){

            jokeFavName = 'fav_text_joke';
            jokeIndex = _textJokes.indexWhere((textJokes) => textJokes.id == jokeId);
            removeJoke = _textJokes[jokeIndex].isFaved;
          }else{
            jokeFavName = 'fav_image_joke';
            jokeIndex = _imageJokes.indexWhere((imageJokes) => imageJokes.id == jokeId);
            removeJoke = _imageJokes[jokeIndex].isFaved;
          }

          if(!removeJoke){
           await Firestore.instance
            .collection('users')
            .document(currentUser.userId)
            .collection(jokeFavName).document(jokeId).setData
            ({'jokeId': jokeId, 'dateAdded': DateFormatter.dateToString(DateTime.now())}).then((onValue){
                       if(jokeType == JokeType.text){
                             _textJokes[jokeIndex].isFaved = !_textJokes[jokeIndex].isFaved;
                       }else{
                         _imageJokes[jokeIndex].isFaved = !_imageJokes[jokeIndex].isFaved;
                       }
                       _updateJokeSubject(jokeType); 
            }, onError: (error){
                    
            });
          }else{
            await Firestore.instance
            .collection('users')
            .document(currentUser.userId)
            .collection(jokeFavName).document(jokeId).delete().then((onValue){
                       if(jokeType == JokeType.text){
                             _textJokes[jokeIndex].isFaved = !_textJokes[jokeIndex].isFaved;
                       }else{
                         _imageJokes[jokeIndex].isFaved = !_imageJokes[jokeIndex].isFaved;
                       }
                       _updateJokeSubject(jokeType); 
            }, onError: (error){

            });
          }
    });
    _uploadJokeSubject.stream.listen((Map uploadDetails) async {
      Joke joke = uploadDetails['joke'];
      Map jokeMap = joke.toMap();
      jokeMap.remove('id');
      BlocCompleter completer = uploadDetails['completer'];

      String documentType = '';

       _uploadLoadStatusSubject.sink.add(LoadStatus.loading);

      if (joke is TextJoke) {
        documentType = 'text_jokes';
        await Firestore.instance
            .collection('jokes')
            .document(documentType)
            .collection('content')
            .add(jokeMap).then((onValue){
                         _uploadLoadStatusSubject.sink.add(LoadStatus.loaded);
                         completer.completed(null);
            }, onError: (error){
                     _uploadLoadStatusSubject.sink.add(LoadStatus.error);
                     completer.error(error);
            });

      } else if (joke is ImageJoke) {
        documentType = 'image_jokes';

                          
                          StorageReference ref = FirebaseStorage.instance
                      .ref()
                      .child('joke_images/' + joke.title);
                      
                  StorageUploadTask uploadTask = ref.putFile(uploadDetails['image']);
                  String downloadUrl = await (await uploadTask.onComplete).ref.getDownloadURL();

                   jokeMap['url'] = downloadUrl.toString();
                   await Firestore.instance
                    .collection('jokes')
                    .document(documentType)
                    .collection('content')
                    .add(jokeMap).then((onValue){
                         _uploadLoadStatusSubject.sink.add(LoadStatus.loaded);
                         completer.completed(null);
                    }, onError: (error){
                     _uploadLoadStatusSubject.sink.add(LoadStatus.error);
                     completer.error(error);
            });
      }
    });

    _movieTermToSearchSubject.stream.listen((termToSearch) {
      _movies.add(Movie(
          id: 'www', name: termToSearch, seasons: 5, description: 'ssss'));
      _searchedMovieResultSubject.sink.add(UnmodifiableListView(_movies));

      // Firestore.instance.collection('movies').orderBy('name').startAt([termToSearch]).endAt([termToSearch+'\uf8ff']).snapshots().listen((moviesData){

      //          List<Movie> movies = moviesData.documents
      //             .map((doc) => Movie(
      //                 id: doc.documentID,
      //                 name: doc['name'],
      //                 description: doc['description']))
      //             .toList();
      //           _searchedMovieResultSubject.sink.add(UnmodifiableListView(movies));
      // });
    });

    _getMoviesSubject.stream.listen((Map options) {
      _movieLoadStatusSubject.sink.add(LoadStatus.loading);
      Firestore.instance.collection('movies').snapshots().listen((data) {
        List<Movie> movies = data.documents
            .map((doc) => Movie(
                id: doc.documentID,
                name: doc['name'],
                description: doc['description']))
            .toList();
        _movies = movies;
        _moviesSubject.sink.add(UnmodifiableListView(_movies));
        //modify this for infinite scroll and remove the loadend
        _movieLoadStatusSubject.sink.add(LoadStatus.loadEnd);
      }).onError((err) {
        _movieLoadStatusSubject.sink.add(LoadStatus.error);
      });
    });

    final optionsStream = Observable.combineLatest2(_selectedMovieSubject.stream, _getFavSubject.stream , (Movie selectedMovie , bool getFav){

          return {'selectedMovie': selectedMovie , 'getFav': getFav};

    });
   
    _getJokesSubject.stream.withLatestFrom(optionsStream,
        (Map map, Map options) {
          map['selectedMovie'] = options['selectedMovie'];
          map['getFav'] = options['getFav'];
          return map;
    }).listen((Map map) { 
      JokeType jokeType = map['jokeType'];
      User currentUser = map['currentUser'];
      int currentPage =
          (jokeType == JokeType.image) ? _currentImagePage : _currentTextPage;
      Movie movie = map['selectedMovie'];
      bool getFav = map['getFav'];
      
      _showJokeLoading(jokeType);

      Query jokesQuery;

      if(!getFav){
        jokesQuery = _generateJokeQuery(jokeType, currentPage, movie);
      }else{
        jokesQuery = _generateFavJokeQuery(jokeType, currentPage, currentUser);
      }


      // .limit(4).snapshots().listen((fav){
      //                 List<DocumentSnapshot> jokesSnapshot = [];
      //                 fav.documents.forEach((favz) async{
      //                         DocumentSnapshot doc =   await Firestore.instance.collection('jokes').document('image_jokes').collection('content').document(favz.documentID).get();
      //                         jokesSnapshot.add(doc);
      //                 });
      // });

      jokesQuery.snapshots().listen((jokes) async {
        if (jokes.documents.isNotEmpty) {

            List<DocumentSnapshot> jokesSnapshot = [];
          if(getFav){
                             
                      for(int i = 0 ; i < jokes.documents.length; i++){
                              DocumentSnapshot doc =   await Firestore.instance.collection('jokes').document('image_jokes').collection('content').document(jokes.documents[i].documentID).get();
                              jokesSnapshot.add(doc);
                    
                      }
          }else{
            jokesSnapshot = jokes.documents;
          }
          
          _setLastJoke(jokeType, jokesSnapshot[jokesSnapshot.length - 1]);
          final gottenJokes = await _createJokeList(jokesSnapshot, jokeType, movie, currentUser);
          if (currentPage == 1) {
            _addJokes(gottenJokes, jokeType);
            _updateJokeSubject(jokeType);
            _setLoadStatusSubject(jokeType, LoadStatus.loaded);
            _incrementPage(jokeType);
          } else {
            _addJokes(gottenJokes, jokeType, append: true);
            _updateJokeSubject(
                jokeType); //TODO: check if it prevents isEmpty text from appearing briefly
            _setLoadStatusSubject(jokeType, LoadStatus.loadedMore);
          }
        } else {
          //TODO: check if the list will show empty when previous items already exist and the movie type is changed. if it doesn't,
          //uncomment the code below
          if (currentPage == 1) {
            _addJokes([], jokeType);
            _updateJokeSubject(jokeType);
          }
          _setLoadStatusSubject(jokeType, LoadStatus.loadEnd);
        }
      });
    });
  }

  Query _generateJokeQuery(JokeType jokeType, int currentPage, Movie movie){

     String jokePath =
          (jokeType == JokeType.image) ? 'image_jokes' : 'text_jokes';

     Query jokesQuery = Firestore.instance
          .collection('jokes')
          .document(jokePath)
          .collection('content')
          .orderBy('title'); //TODO: change order to dateAdded

          if (currentPage > 1) {
        jokesQuery = jokesQuery.startAfter((jokeType == JokeType.image)
            ? [_lastImageJoke['title']]
            : [_lastTextJoke['title']]);
      }

      if (movie.id != null) {
        jokesQuery = jokesQuery.where('movie', isEqualTo: movie.id);
      }


        return jokesQuery.limit(4);

  }

  Query _generateFavJokeQuery(JokeType jokeType, int currentPage, User currentUser){

        String favJokePath =
          (jokeType == JokeType.image) ? 'fav_image_joke' : 'fav_text_joke';

        Query jokesQuery = Firestore.instance.collection('users').document(currentUser.userId).collection(favJokePath).orderBy('dateAdded');

         if (currentPage > 1) {
        jokesQuery = jokesQuery.startAfter((jokeType == JokeType.image)
            ? [_lastImageJoke['dateAdded']]
            : [_lastTextJoke['dateAdded']]);
      }
      return jokesQuery.limit(4);
  }

  _showJokeLoading(jokeType){
    int currentPage =
          (jokeType == JokeType.image) ? _currentImagePage : _currentTextPage;
     if (currentPage > 1) {
        _setLoadStatusSubject(jokeType, LoadStatus.loadingMore);
      } else {
        _setLoadStatusSubject(jokeType, LoadStatus.loading);
      }

  }

  _getMovieFromCache(String movieId) {
    if (movieCache.containsKey(movieId)) {
      return movieCache[movieId];
    }
    return null;
  }

  _getMovieFromList(String movieId) {
    return _movies.firstWhere((movie) => movie.id == movieId);
  }

  _setLastJoke(JokeType jokeType, joke) {
    if (jokeType == JokeType.image) {
      _lastImageJoke = joke;
    } else {
      _lastTextJoke = joke;
    }
  }

  _updateJokeSubject(JokeType jokeType) {
    if (jokeType == JokeType.image) {
      _imageJokesSubject.sink.add(UnmodifiableListView(_imageJokes));
    } else {
      _textJokesSubject.sink.add(UnmodifiableListView(_textJokes));
    }
  }

  _addJokes(List<Joke> jokes, JokeType jokeType, {bool append = false}) {
    if (jokeType == JokeType.image) {
      List<ImageJoke> imageJokes = jokes.cast<ImageJoke>();
      (!append)
          ? _imageJokes = imageJokes
          : _imageJokes.addAll(imageJokes); //check this
    } else {
      List<TextJoke> textJoke = jokes.cast<TextJoke>();
      if (!append) {
        _textJokes = textJoke;
      } else {
        _textJokes.addAll(textJoke);
      }
    }
  }

  Future<List<Joke>> _createJokeList(
      List<DocumentSnapshot> jokeDocuments, JokeType jokeType, Movie movie, User currentUser) async {
   
   
    List<Joke> jokes = jokeDocuments.map((joke){
      Map jokeData = joke.data;
      jokeData['id'] = joke.documentID;

      if (movie == null) {
        movie = _getMovieFromCache(jokeData['movie']);
        if (movie == null) {
          movie = _getMovieFromList(jokeData['movie']);
        }
      }
      jokeData['movie'] = movie;
      jokeData ['isFaved'] = false;
      return _getJokeFromMap(jokeType, jokeData);
    }).toList();

    if(currentUser != null){
      for(int i = 0 ; i < jokes.length ; i++){
            jokes[i].isFaved = await _isJokeFaved(jokes[i].id, currentUser, jokeType);
      }
    }
    return jokes;


    // List<Future<Joke>> jokes = jokeDocuments.map((joke) async{
    //   Map jokeData = joke.data;
    //   jokeData['id'] = joke.documentID;

    //   if (movie == null) {
    //     movie = _getMovieFromCache(jokeData['movie']);
    //     if (movie == null) {
    //       movie = _getMovieFromList(jokeData['movie']);
    //     }
    //   }
    //   jokeData['movie'] = movie;
    //   jokeData ['isFaved'] = (currentUser != null) ? await _isJokeFaved(joke.documentID, currentUser, jokeType) : false;
    //   return _getJokeFromMap(jokeType, jokeData);
    // }).toList();
    // List<Joke> jjk =  await Future.wait(jokes);
    // return jjk;
  
  }

  Future<bool> _isJokeFaved(String jokeId, User currentUser, JokeType jokeType) async{

    String jokeFavName = '';
       if(jokeType == JokeType.text){
            jokeFavName = 'fav_text_joke';
          }else{
            jokeFavName = 'fav_image_joke';
          }
      DocumentSnapshot favSnapshot =  await Firestore.instance
            .collection('users')
            .document(currentUser.userId)
            .collection(jokeFavName).document(jokeId).get();
      return (favSnapshot.exists) ? true : false;
  }



  Joke _getJokeFromMap(JokeType jokeType, Map jokeData){
      if (jokeType == JokeType.image) {
        return ImageJoke.fromMap(jokeData); //TODO: handle if movie is null
      } else {
        return TextJoke.fromMap(jokeData);
      }
  }

  _incrementPage(JokeType jokeType) {
    if (jokeType == JokeType.image) {
      _currentImagePage++;
    } else if (jokeType == JokeType.text) {
      _currentTextPage++;
    }
  }

  _setLoadStatusSubject(JokeType jokeType, LoadStatus loadStatus) {
    if (jokeType == JokeType.image) {
      _imageLoadStatusSubject.sink.add(loadStatus);
    } else if (jokeType == JokeType.text) {
      _textLoadStatusSubject.sink.add(loadStatus);
    }
  }


  _addTextJokesToServer() async {
    String friends = '9KfSaN86fI4plZHqURmX';
    String himym = 'IHDbyYe2a8D9xhmZ1nkY';

    final textJokes = [
      TextJoke(
          title: 'achan',
          text: 'knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'bross',
          text: 'ros knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'crach',
          text: 'knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'djoe',
          text: 'knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'ephoebe',
          text: 'dd knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'fjennis',
          text: 'jen hahaha knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'g2chan',
          text: 'knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'h2ross',
          text: 'ros knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'i2rach',
          text: 'knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'j2joe',
          text: 'knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'k2phoebe',
          text: 'dd knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'l2jennis',
          text: 'jen hahaha knock knock',
          likes: 1,
          movie: Movie(id: friends),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'mabarney',
          text: 'legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'mbrobin',
          text: 'ff legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'mcted',
          text: ' rr legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'mdmarshal',
          text: 'rrw legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'melily',
          text: ' rr legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: 'mother',
          text: 'legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: '2barney',
          text: 'legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: '2robin',
          text: 'ff legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: '2ted',
          text: ' rr legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: '2marshal',
          text: 'rrw legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: '2lily',
          text: ' rr legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
      TextJoke(
          title: '2mother',
          text: 'legendary',
          likes: 1,
          movie: Movie(id: himym),
          dateAdded: DateTime.now()),
    ];

    const startAlpha = 97;
    const endAlpha = 122;

    for (var i = startAlpha; i <= endAlpha; i++) {
      var joke;
      if (i < (startAlpha + endAlpha) / 2) {
        joke = TextJoke(
            title: String.fromCharCode(i) + 'friends',
            text: 'friends',
            likes: i,
            movie: Movie(id: friends),
            dateAdded: DateTime.now());
      } else {
        joke = TextJoke(
            title: String.fromCharCode(i) + 'himym',
            text: 'himym',
            likes: i,
            movie: Movie(id: himym),
            dateAdded: DateTime.now());
      }

      Map jokeMap = joke.toMap();
      jokeMap.remove('id');
      await Firestore.instance
          .collection('jokes')
          .document('text_jokes')
          .collection('content')
          .add(jokeMap);
    }

    // textJokes.forEach((joke) async {
    //   Map jokeMap = joke.toMap();
    //   jokeMap.remove('id');
    //   await Firestore.instance
    //       .collection('jokes')
    //       .document('text_jokes')
    //       .collection('content')
    //       .add(jokeMap);
    // });
    // Firestore.instance.collection('jokes').document('text_jokes').collection('content').add(data);
  }

  _addImageJokeToServer() {
    String friends = '9KfSaN86fI4plZHqURmX';
    String himym = 'IHDbyYe2a8D9xhmZ1nkY';

    final jokeImageList = [
      ImageJoke(
          title: '1chan',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '2chan',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '3chan',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '4chan',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '1ross',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '2ross',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '3ross',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '4ross',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '1mon',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '2mon',
          movie: Movie(id: friends),
          likes: 23,
          url: 'hello',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '1ted',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '2ted',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '3ted',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '4ted',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '1ban',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '2ban',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '3ban',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '4ban',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '1rob',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
      ImageJoke(
          title: '2rob',
          movie: Movie(id: himym),
          likes: 23,
          url: 'himym',
          dateAdded: DateTime.now()),
    ];

    jokeImageList.forEach((joke) async {
      Map jokeMap = joke.toMap();
      jokeMap.remove('id');
      await Firestore.instance
          .collection('jokes')
          .document('image_jokes')
          .collection('content')
          .add(jokeMap);
    });
  }

  close() {
    _moviesSubject.close();
    _imageJokesSubject.close();
    _textJokesSubject.close();
    _getJokesSubject.close();
    _imageLoadStatusSubject.close();
    _textLoadStatusSubject.close();
    _selectedMovieSubject.close();
    _getMoviesSubject.close();
    _movieLoadStatusSubject.close();
    _searchedMovieResultSubject.close();
    _movieTermToSearchSubject.close();
    _uploadJokeSubject.close();
    _uploadLoadStatusSubject.close();
  }
}
