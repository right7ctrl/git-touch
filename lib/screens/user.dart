import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:git_touch/models/theme.dart';
import 'package:git_touch/scaffolds/refresh_stateful.dart';
import 'package:git_touch/screens/settings.dart';
import 'package:git_touch/screens/users.dart';
import 'package:git_touch/utils/utils.dart';
import 'package:git_touch/widgets/action_entry.dart';
import 'package:git_touch/widgets/app_bar_title.dart';
import 'package:git_touch/screens/repositories.dart';
import 'package:git_touch/widgets/entry_item.dart';
import 'package:git_touch/widgets/table_view.dart';
import 'package:git_touch/widgets/text_contains_organization.dart';
import 'package:git_touch/widgets/user_contributions.dart';
import 'package:git_touch/widgets/user_item.dart';
import 'package:github_contributions/github_contributions.dart';
import 'package:git_touch/models/auth.dart';
import 'package:provider/provider.dart';
import 'package:git_touch/widgets/repository_item.dart';
import 'package:git_touch/widgets/action_button.dart';
import 'package:primer/primer.dart';

class UserScreen extends StatelessWidget {
  final String login;
  final bool isOrganization;

  UserScreen(this.login, {this.isOrganization = false});

  Future queryUser(BuildContext context) async {
    var _login = login ?? Provider.of<AuthModel>(context).activeAccount.login;
    var data = await Provider.of<AuthModel>(context).query('''
{
  user(login: "$_login") {
    $userGqlChunk
    company
    location
    email
    websiteUrl
    starredRepositories {
      totalCount
    }
    followers {
      totalCount
    }
    following {
      totalCount
    }
    repositories(first: 6, ownerAffiliations: OWNER, orderBy: {field: STARGAZERS, direction: DESC}) {
      totalCount
      nodes {
        $repoChunk
      }
    }
    pinnedItems(first: 6) {
      nodes {
        ... on Repository {
          $repoChunk
        }
      }
    }
    viewerCanFollow
    viewerIsFollowing
    url
  }
}
''');
    return data['user'];
  }

  Future queryOrganization(BuildContext context) async {
    // Use pinnableItems instead of organization here due to token permission
    var data = await Provider.of<AuthModel>(context).query('''
{
  organization(login: "$login") {
    login
    name
    avatarUrl
    description
    location
    email
    websiteUrl
    url
    pinnedItems(first: 6) {
      nodes {
        ... on Repository {
          $repoChunk
        }
      }
    }
    pinnableItems(first: 6, types: [REPOSITORY]) {
      totalCount
      nodes {
        ... on Repository {
        	$repoChunk
        }
      }
    }
    membersWithRole {
      totalCount
    }
  }
}
''');
    return data['organization'];
  }

  Future<List<ContributionsInfo>> fetchContributions(
      BuildContext context) async {
    var _login = login ?? Provider.of<AuthModel>(context).activeAccount.login;
    switch (Provider.of<AuthModel>(context).activeAccount.platform) {
      case PlatformType.gitlab:
        return [];
      default:
        try {
          return await getContributions(_login);
        } catch (err) {
          return [];
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshStatefulScaffold(
      fetchData: () {
        return Future.wait(
          isOrganization
              ? [
                  queryOrganization(context),
                  Future.value([].cast<ContributionsInfo>())
                ]
              : [
                  queryUser(context),
                  fetchContributions(context),
                ],
        );
      },
      title: AppBarTitle(isOrganization ? 'Organization' : 'User'),
      actionBuilder: (payload) {
        var data = payload.data;

        if (isOrganization) {
          return ActionButton(
            title: 'Organization Actions',
            items: [
              if (data != null) ...[
                ActionItem.share(payload.data[0]['url']),
                ActionItem.launch(payload.data[0]['url']),
              ],
            ],
          );
        }

        if (login == null) {
          return ActionEntry(
            iconData: Icons.settings,
            onTap: () {
              Provider.of<ThemeModel>(context).pushRoute(
                  context, (_) => SettingsScreen(),
                  fullscreenDialog: true);
            },
          );
        } else {
          return ActionButton(
            title: 'User Actions',
            items: [
              if (data != null && data[0]['viewerCanFollow'])
                ActionItem(
                  text: data[0]['viewerIsFollowing'] ? 'Unfollow' : 'Follow',
                  onPress: () async {
                    if (data[0]['viewerIsFollowing']) {
                      await Provider.of<AuthModel>(context)
                          .deleteWithCredentials('/user/following/$login');
                      data[0]['viewerIsFollowing'] = false;
                    } else {
                      Provider.of<AuthModel>(context)
                          .putWithCredentials('/user/following/$login');
                      data[0]['viewerIsFollowing'] = true;
                    }
                  },
                ),
              if (data != null) ...[
                ActionItem.share(data[0]['url']),
                ActionItem.launch(data[0]['url']),
              ],
            ],
          );
        }
      },
      bodyBuilder: (payload) {
        var data = payload.data[0];
        var contributions = payload.data[1];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            UserItem(
              login: data['login'],
              name: data['name'],
              avatarUrl: data['avatarUrl'],
              bio: isOrganization ? data['description'] : data['bio'],
              inUserScreen: true,
            ),
            CommonStyle.border,
            Row(children: [
              if (isOrganization) ...[
                EntryItem(
                  count: data['pinnableItems']['totalCount'],
                  text: 'Repositories',
                  screenBuilder: (context) =>
                      RepositoriesScreen.ofOrganization(data['login']),
                ),
                EntryItem(
                  count: data['membersWithRole']['totalCount'],
                  text: 'Members',
                  screenBuilder: (context) =>
                      UsersScreen.members(data['login']),
                ),
              ] else ...[
                EntryItem(
                  count: data['repositories']['totalCount'],
                  text: 'Repositories',
                  screenBuilder: (context) => RepositoriesScreen(data['login']),
                ),
                EntryItem(
                  count: data['starredRepositories']['totalCount'],
                  text: 'Stars',
                  screenBuilder: (context) =>
                      RepositoriesScreen.stars(data['login']),
                ),
                EntryItem(
                  count: data['followers']['totalCount'],
                  text: 'Followers',
                  screenBuilder: (context) =>
                      UsersScreen.followers(data['login']),
                ),
                EntryItem(
                  count: data['following']['totalCount'],
                  text: 'Following',
                  screenBuilder: (context) =>
                      UsersScreen.following(data['login']),
                ),
              ]
            ]),
            CommonStyle.verticalGap,
            if (contributions.isNotEmpty) ...[
              UserContributions(contributions),
              CommonStyle.verticalGap,
            ],
            TableView(
              hasIcon: true,
              items: [
                if (!isOrganization && isNotNullOrEmpty(data['company']))
                  TableViewItem(
                    leftIconData: Octicons.organization,
                    text: TextContainsOrganization(data['company'],
                        style: TextStyle(
                            fontSize: 16, color: PrimerColors.gray900),
                        overflow: TextOverflow.ellipsis),
                  ),
                if (isNotNullOrEmpty(data['location']))
                  TableViewItem(
                    leftIconData: Octicons.location,
                    text: Text(data['location']),
                    onTap: () {
                      launchUrl('https://www.google.com/maps/place/' +
                          (data['location'] as String)
                              .replaceAll(RegExp(r'\s+'), ''));
                    },
                  ),
                if (isNotNullOrEmpty(data['email']))
                  TableViewItem(
                    leftIconData: Octicons.mail,
                    text: Text(data['email']),
                    onTap: () {
                      launchUrl('mailto:' + data['email']);
                    },
                  ),
                if (isNotNullOrEmpty(data['websiteUrl']))
                  TableViewItem(
                    leftIconData: Octicons.link,
                    text: Text(data['websiteUrl']),
                    onTap: () {
                      var url = data['websiteUrl'] as String;
                      if (!url.startsWith('http')) {
                        url = 'http://$url';
                      }
                      launchUrl(url);
                    },
                  ),
              ],
            ),
            ...buildPinnedItems(
                data['pinnedItems']['nodes'],
                data[isOrganization ? 'pinnableItems' : 'repositories']
                    ['nodes']),
            CommonStyle.verticalGap,
          ],
        );
      },
    );
  }
}
