# Overview

This document described the Media Cloud Topics API.  The Topics API is a subset of the larger Media Cloud API.  The Topics API provides access to data about Media Cloud Topics and related data.  For a fuller understanding of Media Cloud data structures and for information about *Authentication*, *Request Limits*, the API *Python Client*, and *Errors*, see the documentation for the main [link: main api] Media Cloud API.

The topics api is currently under development and is available only to Media Cloud team members and select beta testers.  Email us at info@mediacloud.org if you would like to beta test the Topics API.

A *topic* currently may be created only by the Media Cloud team, though we occasionally run topics for external researchers.



## Media Cloud Crawler and Core Data Structures

The core Media Cloud data are stored as *media*, *feeds*, and *stories*.  

A *medium* (or *media source*) is a publisher, which can be a big mainstream media publisher like the New York Times, an
activist site like fightforthefuture.org, or even a site that does not publish regular news-like stories, such as Wikipedia.  

A *feed* is a syndicated feed (RSS, RDF, ATOM) from which Media Cloud pulls stories for a given *media source*.  A given
*media source* may have anywhere from zero *feeds* (in which case we do not regularly crawl the site for new content) up
to hundreds of feeds (for a site like the New York Times to make sure we collect all of its content).

A *story* represents a single published piece of content within a *media source*.  Each *story* has a unique url within
a given *media source*, even though a single *story* might be published under multiple urls.  Media Cloud tries
to deduplicate stories by title.

The Media Cloud crawler regularly downloads every *feed* within its database and parses out all urls from each *feed*.
It downloads every new url it discovers and adds a *story* for that url, as long as the story is not a duplicate for
the given *media source*.  The Media Cloud archive consists primarily of *stories* collected by this crawler.

## Topic Data Structures

A Media Cloud *topic* is a set of stories relevant to some subject.  The topic spider starts by searching for a
set of stories relevant to the story within the Media Cloud archive and then spiders urls from those
stories to find more relevant stories, then iteratively repeats the process 15 times.

After the spidering is complete, a *topic* consists of a set of relevant *stories*, *links* between those stories, the
*media* that published those *stories*, and social media metrics about the *stories* and *media.  The various topics/
end points provide access to all of this raw data as well as various of various analytical processes applied to this
data.

## API URLs

All urls in the topics api are in the form:

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/list?key=KEY`

For example, the following will return all stories in the latest snapshot of topic id 1344.

`https://api.mediacloud.org/api/v2/topics/1344/stories/list?key=KEY`

## Snapshots, Timespans, and Frames

Each *topic* is viewed through one of its *snapshots*.  A *snapshot* is static dump of all data from a topic at
a given point in time.  The data within a *snapshot* will never change, so changes to a *topic* are not visible
until a new *snapshot* is made.

Within a *snapshot*, data can be viewed overall, or through some combination of a *frame* and a *timespan*.

A *frame* consists of a subset of stories within a *topic* defined by some user configured *framing method*.  For
example, a 'trump' *frame* within a 'US Election' *topic* would be defined using the 'Boolean Query' *framing method*
as all stories matching the query 'trump'.  *Frames* can be collected together in a *Frame Set* for easy comparison.

A *timespan* displays the *topic* as if it exists only of stories either published within the date range of the
*timespan* or linked to by a story published within the date range of the *timespan*.

*Topics*, *snapshots*, *frames*, and *timespans* are strictly hierarchical.  Every *snapshot* belongs to a single
*topic*.  Every *frame* belongs to a single *snapshot*, and every timespan* belongs to either a single *frame* or the
null *frame*.  Specifying a *frame* implies the parent *snapshot* of that *frame*.  Specifying a *topic* implies the
parent *frame* (and by implication the parent *snapshot*), or else the null *frame* within the parent *snapshot*.

The hierarchy of *topics*, *snapshots*, *frames*, and *timespans* looks like this:

* topic
  * snapshot
    * frame
      * timespan

Every url that returns data from a *topic* accepts optional *spanshots_id*, *timespans_id*, and *frames_id* parameters.

If no *snapshots_id* is specified, the call returns data from the latest *snapshot* generated for the *topic*.  If no
*timespans_id* is specified, the call returns data from the overall *timespan* of the given *snapshot* and *frame*.  If
no *frames_id* is specified, the call assumes the null *frame*.  If multiple of these parameters are specified,
they must point to the same *topic* / *snapshot* / *frame* / *timespan* or an error will be returned (for instance, a
call that specifies a *snapshots_id* for a *snapshot* in a *topic* different from the one specified in the url, an error
will be returned).

## Paging

For calls that support paging, each url supports a *limit* parameter and a *link_id* paramter.  For these calls, only *limit* results will be returned at a time, and a set of *link_ids* will be returned along with the results.  To get the current set of results again, or the previous or next page of results, call the same end point with only the *key* and *link_id* parameters.  The *link_id* parameter includes state that remembers all of the parameters from the original call.

For example, the following a paged response: 

```json
{
  stories:
  [ 
    {   
   	  stories_id: 168326235,
	  media_id: 18047,
	  bitly_click_count: 182,
      collect_date: "2013-10-26 09:25:39",
      publish_date: "2012-10-24 16:09:26",
      inlink_count: 531,
      language: "en",
      title: "Donald J. Trump (realDonaldTrump) on Twitter",
      url: "https://twitter.com/realDonaldTrump",
      outlink_count: 0,
      guid: "https://twitter.com/realDonaldTrump"
    }
  ],
  link_ids:
  {
    current: 123456,
    previous: 456789,
    next: 789123
  }
}
```

After receiving that reponse, you can use the following url with no other parameters to fetch the next page of results:

`https://api.mediacloud.org/api/v2/topics/1/stories/list?key=KEY&link_id=789123`

When the system has reached the end of the results, it will return an empty list and a null 'next' link_id.

link_ids are persistent — they can be safely used to refer to a given result forever (for instance, as an identifier for a link shortener).

## Examples

The section for each end point includes an example call and response for that end point.  For end points that return multiple results, we generally only show a single result (for instance a single story) for the sake of documentation brevity.

# Topics

## topics/list

`https://api.mediacloud.org/api/v2/topics/list`

The topics/list call returns a simple list of topics available in Media Cloud.  The topics/list call is is only call
that does not include a topics_id in the url.

### Query Parameters

(no parameters)

### Output Description

| Field               | Description                              |
| ------------------- | ---------------------------------------- |
| topics_id           | topic id                                 |
| name                | human readable label                     |
| pattern             | regular expression derived from solr query |
| solr_seed_query     | solr query used to generate seed stories |
| solr_seed_query_run | boolean indicating whether the solr seed query has been run to seed the topic |
| description         | human readable description               |
| max_iterations      | maximum number of iterations for spidering |

### Example

Fetch all topics in Media Cloud:

`https://api.mediacloud.org/api/v2/topics/list`

Response:

```json
{
  topics:
  [
  	{
      topics_id: 672,
      name: "network neutrality",
      patern: "[[:<:]]net.*neutrality",
      solr_seed_query: "net* and neutrality and +tags_id_media:(8875456 8875460 8875107 8875110 8875109 8875111 8875108 8875028 8875027 8875114 8875113 8875115 8875029 129 2453107 8875031 8875033 8875034 8875471 8876474 8876987 8877928 8878292 8878293 8878294 8878332) AND +publish_date:[2013-12-01T00:00:00Z TO 2015-04-24T00:00:00Z]",
      solr_seed_query_run: 1,
      description: "network neutrality",
      max_iterations: 15
	}
  ]
}
```



# Stories

## stories/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/list`

The stories list call returns stories in the topic.

### Query Parameters

| Parameter            | Default | Notes                                    |
| -------------------- | ------- | ---------------------------------------- |
| q                    | null    | if specified, return only stories that match the given solr query |
| sort                 | inlink  | sort field for returned stories; possible values: `inlink`, `social` |
| stories_id           | null    | return only stories matching these storie_ids |
| link_to_stories_id   | null    | return only stories from other media that link to the given stories_ids |
| link_from_stories_id | null    | return only stories from other media that are linked from the given stories_ids |
| media_id             | null    | return only stories belonging to the given media_ids |
| limit                | 20      | return the given number of stories       |
| link_id              | null    | return stories using the paging link     |

The call will return an error if more than one of the following parameters are specified: `q`, `stories_id`, `link_to_stories`, `link_from_stories_id`, `media_id`.

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](api_2_0_spec.md) in the main API spec.

Standard parameters accepted: snapshots_id, frames_id, timespans_id, limit, links_id.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| stories_id           | story id                                 |
| media_id             | media source id                          |
| url                  | story url                                |
| title                | story title                              |
| guid                 | story globally unique identifier         |
| language             | two letter code for story language       |
| publish_date         | publication date of the story, or 'undateable' if the story is not dateable |
| collect_date         | date the story was collected             |
| date_guess_method    | method used to guess the publish_date    |
| inlink_count         | count of hyperlinks from stories in other media in this timespan |
| outlink_count        | count of hyperlinks to stories in other media in this timespan |
| bitly_click_count    | number of clicks on bitly links that resolve to this story's url |
| facebook_share_count | number of facebook shares for this story's url |

### Example

Fetch all stories in topic id 1344:

`https://api.mediacloud.org/api/v2/topics/1344/stories/list`

Response:

```json
{
  stories:
  [ 
    {   
   	  stories_id: 168326235,
	  media_id: 18047,
	  bitly_click_count: 182,
      collect_date: "2013-10-26 09:25:39",
      publish_date: "2012-10-24 16:09:26",
      date_guess_method: 'guess_by_og_article_published_time',
      inlink_count: 531,
      language: "en",
      title: "Donald J. Trump (realDonaldTrump) on Twitter",
      url: "https://twitter.com/realDonaldTrump",
      outlink_count: 0,
      guid: "https://twitter.com/realDonaldTrump"
    }
  ],
  link_ids:
  {
    current: 123456,
    previous: 456789,
    next: 789123
  }
}
```

## stories/count

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/count`

Return the number of stories that match the query.

### Query Parameters

| Parameter | Default | Notes                               |
| --------- | ------- | ----------------------------------- |
| q         | null    | count stories that match this query |

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2stories_publiclist) in the main API spec.

Standard parameters accepted: snapshots_id, frames_id, timespans_id, limit, links_id.

### Output Description

| Field | Description                |
| ----- | -------------------------- |
| count | number of matching stories |

### Example

Return the number of stories that mention 'immigration' in the 'US Election' topic:

`https://api.mediacloud.org/api/v2/topics/<topics_id>/stories_count?q=immigration`

Response:

```json
{
  count: 123
}
```

# Sentences

## sentences/count

`https://api.mediacloud.org/api/v2/topics/<topics_id>/sentences/count`

Return the numer of sentences that match the query, optionally split by date.

The topics `sentences/count` call is identical to the `sentences/count` call in the main API, except that the topics version accepts the snapshots_id, frames_id, and timespans_id parameters and returns counts only for stories within the topic.

For details about this end point, including parameters, output, and examples, see the [main API](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2sentencescount).

# Media

## media/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/media/list`

The media list call returns the list of media in the topic.

### Query Parameters

| Parameter | Default | Notes                                    |
| --------- | ------- | ---------------------------------------- |
| media_id  | null    | return only the specified media          |
| sort      | inlink  | sort field for returned stories; possible values: `inlink`, `social` |
| name      | null    | search for media with the given name     |
| limit     | 20      | return the given number of media         |
| link_id   | null    | return media using the paging link       |

If the `name` parameter is specified, the call returns only media sources that match a case insensitive search specified value. If the specified value is less than 3 characters long, the call returns an empty list.

Standard parameters accepted: snapshots_id, frames_id, timespans_id, limit, links_id.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| media_id             | medium id                                |
| name                 | human readable label for medium          |
| url                  | medium url                               |
| story_count          | number of stories in medium              |
| inlink_count         | sum of the inlink_count for each story in the medium |
| outlink_count        | sum of the outlink_count for each story in the medium |
| bitly_click_count    | sum of the bitly_click_count for each story in the medium |
| facebook_share_count | sum of the facebook_share_count for each story in the medium |

### Example

Return all stories in the medium that match 'twitt':

`https://api.mediacloud.org/api/v2/topics/<topics_id>/media/list?name=twitt`

Response:

```json
{
  media: 
  [
    {
      bitly_click_count: 303,
      media_id: 18346,
      story_count: 3475,
      name: "Twitter",
      inlink_count: 8454,
      url: "http://twitter.com",
      outlink_count: 72,
      facebook_share_count: 123
    }
  ],
  link_ids:
  {
    current: 123456,
    previous: 456789,
    next: 789123
  }
}
```



# Frames

A *frame* is a set of stories identified through some *framing method*.  *Frame Sets* are sets of *frames* that share a *framing method* and are also usually som substantive theme determined by the user.  For example, a 'U.S. 2016 Election' topic might include a 'Candidates' *frame set* that includes 'trump' and 'clinton' frames, each of which uses a 'Boolean Query' *framing methodology* to identify stories relevant to each candidate with a separate boolean query for each.

A specific *frame* exists within a specific *snapshot*.  A single topic might have many 'clinton' *frames*, one for each *snapshot*.  Each *topic* has a number of *frame definion*, each of which tells the system which *frames* to create each time a new *snapshot* is created.  *Frames* for new *frame definitions* will be only be created for *snapshots* created after the creation of the *frame definition*.

The relationship of these objects is show below:

* topic
  * frame set definition
    * frame definition (+ framing method)
  * snapshot
    * frame set
      * frame (+ framing method)

## Framing Methods

Media Cloud currently supports the following framing methods.

* Boolean Query

Details about each framing method are below.  Among other properties, each framing method may or not be exclusive.  Exlcusive framing methods generate *frame sets* in which each story belongs to at most one *frame*.

### Framing Method: Boolean Query

The Boolean Query framing method associates a frame with a story by matching that story with a solr boolean query.  *Frame Sets* generated by the Boolean Query method are not exclusive.

## frame_set_definitions/create (POST)

`https://api.mediacloud.org/api/topics/<topics_id>/frame_sets/create`

Create and return a new *frame set definiition*  within the given *topic*.

### Query Parameters

(no parameters)

### Input Description

| Field          | Description                              |
| -------------- | ---------------------------------------- |
| name           | short human readable label for frame set definition |
| description    | human readable description of frame set definition |
| framing_method | framing method to be used for all frame definitions in this definition |

### Example

Create a 'Candidates' frame set definiition in the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/1344/frame_set_definitions_create`

Input:

```json
{
  name: 'Candidates',
  description: 'Stories relevant to each candidate.'
  framing_methods_id: 123
}
```

Response:

```json
{
  frame_set_definitions: 
  [
    frame_set_definitions_id: 789,
    topics_id: 456,
    name: 'Candidates',
    description: 'Stories relevant to each candidate.'
    framing_method: 'Boolean Query',
  	is_exclusive: 0
  ]
}
```

## frame_set_definitions/update (PUT)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/frame_set_definitions/update/<frame_set_definitions_id>`

Update the given frame set definition.

### Query Parameters

(no parameters)

### Input Parameters

See *frame_set_definitions/create* for a list of fields.  Only fields that are included in the input are modified.

### Example

Update the name and description of the 'Candidates'  frame set definition:

`https://api.mediacloud.org/api/v2/topics/1344/frame_set_definitions/update`

Input:

```json
{
  name: 'Major Party Candidates',
  description: 'Stories relevant to each major party candidate.'
}
```

Response:

```json
{
  frame_set_definitions: 
  [
    frame_set_definitions_id: 789,
    topics_id: 456,
    name: 'Major Party Candidates',
    description: 'Stories relevant to each major party candidate.'
    framing_method: 'Boolean Query',
  	is_exclusive: 0
  ]
}
```

## frame_set_definitions/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/frame_set_definitions/list`

Return a list of all frame set definitions belonging to the given topic.

### Query Parameters

(no parameters)

### Output Description

| Field                    | Description                              |
| ------------------------ | ---------------------------------------- |
| frame_set_definitions_id | frame set defintion id                   |
| name                     | short human readable label for the frame set definition |
| description              | human readable description of the frame set definition |
| framing_method           | framing method used for frames in this set |
| is_exclusive             | boolean that indicates whether a given story can only belong to one frame, based on the framing method |

### Example

List all frame set definitions associated with the 'U.S. 2016 Elections' topic:

`https://api.mediacloud.org/api/v2/topics/1344/frame_set_definitions/list`

Response:

```json
{
  frame_set_definitions: 
  [
    frame_set_definitions_id: 789,
    topics_id: 456,
    name: 'Major Party Candidates',
    description: 'Stories relevant to each major party candidate.'
    framing_method: 'Boolean Query',
  	is_exclusive: 0
  ]
}
```

## frame_sets/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/frame_sets/list`

List all *frame sets* belonging to the current *snapshot* in the given *topic*.

### Query Parameters

Standard parameters accepted: snapshots_id.

### Output Description

| Field          | Description                              |
| -------------- | ---------------------------------------- |
| frame_sets_id  | frame set id                             |
| name           | short human readable label for the frame set |
| description    | human readable description of the frame set |
| framing_method | framing method used to generate the frames in the frame set |
| is_exclusive   | boolean that indicates whether a given story can only belong to one frame, based on the framing method |

### Example

Get a list of *frame sets* in the latest *snapshot* in the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/frame_sets_list`

Response:

```json
{ 
  frame_sets:
  [
  	{
      frame_sets_id: 34567,
      name: 'Candidates',
      description: 'Stories relevant to each candidate.',
      framing_method: 'Boolean Query',
      is_exclusive: 0
    }
  ]
}
```

## frame_definitions/create (POST)

`https://api.mediacloud.org/api/topics/<topics_id>/frame_sets/create/<frame_set_definitions_id>`

Create and return a new *frame definiition*  within the given *topic* and *frame set definition*.

### Query Parameters

(no parameters)

### Input Description

| Field       | Description                              |
| ----------- | ---------------------------------------- |
| name        | short human readable label for frames generated by this definition |
| description | human readable description for frames generated by this definition |
| query       | Boolean Query: query used to generate frames generated by this definition |

The input for the *frame definition* depends on the framing method of the parent *frame set definition*.  The framing method specific input fields are listed last in the table above and are prefixed with the name of applicable framing method.

### Example

Create the 'Clinton' *frame definition* within the 'Candidates' *frame set definition* and the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/frame_definitions/create/789`

Input:

```json
{
  name: 'Clinton',
  description: 'stories that mention Hillary Clinton',
  query: 'clinton'
}
```

Response:

```json
{
  frame_definitions:
  [
    {
      frame_definitions_id: 234,
      name: 'Clinton',
      description: 'stories that mention Hillary Clinton',
      query: 'clinton'
    }
  ]
}
```



## frame_definitions/update (PUT)

`https://api.mediacloud.org/api/v2/topics/<topics_id>/frame_definitions/update/<frame_definitions_id>`

Update the given frame definition.

### Query Parameters

(no parameters)

### Input Description

See *frame_definitions/create* for a list of fields.  Only fields that are included in the input are modified.

### Example

Update the query for the 'Clinton' frame definition:

`https://api.mediacloud.org/api/v2/topics/1344/frame_definitions/update/234`

Input:

```json
{ query: 'clinton and ( hillary or -bill )' }
```

Response:

```json
{
  frame_definitions:
  [
    {
      frame_definitions_id: 234,
      name: 'Clinton',
      description: 'stories that mention Hillary Clinton',
      query: 'clinton and ( hillary or -bill )'
    }
  ]
}
```

## frame_definitions/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/frame_definitions/list/<frame_set_definitions_id>`

List all *frame definitions* belonging to the given *frame set definition*.

### Query Parameters

(no parameters)

### Output Description

| Field       | Description                              |
| ----------- | ---------------------------------------- |
| name        | short human readable label for frames generated by this definition |
| description | human readable description for frames generated by this definition |
| query       | Boolean Query: query used to generate frames generated by this definition |

The output for *frame definition* depends on the framing method of the parent *frame set definition*.  The framing method specific fields are listed last in the table above and are prefixed with the name of applicable framing method.

### Example

List all *frame definitions* belonging to the 'Candidates' *frame set definition* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/frame_definitions_list/234`

Response:

```json
{
  frame_definitions:
  [
    {
      frame_definitions_id: 234,
      name: 'Clinton',
      description: 'stories that mention Hillary Clinton',
      query: 'clinton and ( hillary or -bill )'
    }
  ]
}
```

## frames/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/frames/list/<frame_sets_id>`

Return a list of the *frames* belonging to the given *frame set*.

### Query Parameters

(no parameters)

### Ouput Description

| Field       | Description                              |
| ----------- | ---------------------------------------- |
| frames_id   | frame id                                 |
| name        | short human readable label for the frame |
| description | human readable description of the frame  |
| query       | Boolean Query: query used to generate the frame |

The output for *frame* depends on the framing method of the parent *frame definition*.  The framing method specific fields are listed last in the table above and are prefixed with the name of applicable framing method.

### Example

Get a list of *frames* wihin the 'Candiates' *frame set* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/frames/list/34567`

Response:

```json
{
  frames:
  [
    {
      frames_id: 234,
      name: 'Clinton',
      description: 'stories that mention Hillary Clinton',
      query: 'clinton and ( hillary or -bill )'
    }
  ]
}
```

# Snapshots

Each *snapshot* contains a static copy of all data within a topic at the time the *snapshot* was made.  All data viewable by the Topics API must be viewed through a *snapshot*.

## snapshots/generate

`https://api.mediacloud.org/api/v2/topics/<topics_id>/snapshots/generate`

Generate a new *snapshot* for the given topic.

This is an asynchronous call.  The *snapshot* process will run in the background, and the new *snapshot* will only become visible to the API once the generation is complete.  Only one *snapshot* generation job can run at a time.

### Query Parameters

(no parameters)

### Output Description

| Field      | Description                              |
| ---------- | ---------------------------------------- |
| job_queued | boolean indicating whether snapshot generation job was queued |

### Example

Start a new *snapshot* generation job for the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/generate`

Response:

```json
{ job_queued: 1 }
```

## snapshots/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/snapshots/list`

Return a list of all completed *snapshots* in the given *topic*.

### Query Paramaters

(no parameters)

### Output Description

| Field         | Description                            |
| ------------- | -------------------------------------- |
| snapshots_id  | snapshot id                            |
| snapshot_date | date on which the snapshot was created |

### Example

Return a list of *snapshots* in the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/list`

Response:

```json
{
  snapshots:
  [
	{
      snapshots_id: 6789,
      snapshot_date: '2016-09-29 18:14:47.481252',
    }  
  ]
}
```



# Timespans

Each *timespan* is a view of the *topic* that presents the topic as if it consists only of *stories* within the date range of the given *timespan*.

A *story* is included within a *timespan* if the publish_date of the story is within the *timespan* date range or if the *story* is linked to by a *story* that whose publish_date is within date range of the *timespan*.

## timespans/list

`https://api.mediacloud.org/api/v2/topics/<topics_id>/timespans/list`

Return a list of timespans in the current snapshot.

### Query Parameters

Standard parameters accepts: snapshots_id, frames_id.

### Output Description

| Field             | Description                              |
| ----------------- | ---------------------------------------- |
| timespans_id      | timespan id                              |
| period            | type of period covered by timespan; possible values: overall, weekly, monthly, custom |
| start_date        | start of timespan date range             |
| end_date          | end of timespan date range               |
| story_count       | number of stories in timespan            |
| story_link_count  | number of cross media story links in timespan |
| medium_count      | number of distinct media associated with stories in timespan |
| medium_link_count | number of cros media media links in timespan |
| model_r2_mean     | timespan modeling r2 mean                |
| model_r2_sd       | timespan modeling r2 standard deviation  |
| top_media         | number of media include in modeled top media list |

Every *topic* generates the following timespans for every *snapshot*:

* overall - an timespan that includes every story in the topic
* custom all - a custom period timespan that includes all stories within the date range of the topic
* weekly - a weekly timespan for each calendar week in the date range of the topic
* monthly - a monthly timespan for each calendar month in the date range of the topic

Media Cloud needs to guess the date of many of the stories discovered while topic spidering.  We have validated the date guessing to be about 87% accurate for all methods other than the finding a url in the story url.  The possiblity of significant date errors make it possible for the Topic Mapper system to wrongly assign stories to a given timespan and to also miscount links within a given timespan (due to stories getting misdated into or out of a given timespan).  To mitigate the risk of drawing the wrong research conclusions from a given timespan, we model what the timespan might look like if dates were wrong with the frequency that our validation tell us that they are wrong within a given timespan.  We then generate a pearson's correlation between the ranks of the top media for the given timespan in our actual data and in each of ten runs of the modeled data.  The model_* fields provide the mean and standard deviations of the square of those correlations.

### Example

Return all *timespans* associated with the latest *snapshot* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/timespans/list`

Response:

```json

```



## timespans/add_dates (PUT)

# TODO

Stuff left to add:

* clarify snapshots_id / frames_id / timespans_id for all calls
* topics/mine
* topic acls

# QUESTIONS

