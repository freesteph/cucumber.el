# cucumber.el

Emacs mode for editing plain text user stories

## Installation

### Manual

Copy all the files to ~/.emacs.d/elisp/feature-mode, for example,
and add this to your .emacs to load the mode

```lisp
(add-to-list 'load-path "~/.emacs.d/elisp/feature-mode")
```

### Package.el

`feature-mode` is available in both [Marmalade](http://marmalade-repo.org)
and [MELPA](http://melpa.milkbox.net).

You can install it with the following command:

```
M-x package-install feature-mode
```


### Optional configurations

Set default language if .feature doesn't have "# language: fi"
```lisp
(setq feature-default-language "fi")
```

A copy of [the Gherkin
translations](https://github.com/cucumber/gherkin/blob/main/gherkin-languages.json)
is shipped with the repo to figure out translations. Should you need
to override it:

```lisp
(setq feature-i18n-file "/path/to/gherkin/gem/gherkin-translations.json")
```

Load feature-mode
```lisp
(require 'feature-mode)
(add-to-list 'auto-mode-alist '("\.feature$" . feature-mode))
```

Point goto-step-definition capability to your step definitions
```lisp
(setq feature-step-search-path "features/**/*steps.rb")
(setq feature-step-search-gems-path "gems/ruby/*/gems/*/**/*steps.rb")
```

The `feature-step-search-gems-path` variable points to where you have extra
gems installed that have extra step definitions. For example, if you use
[bundler](https://github.com/bundler/bundler) to install gems for your
project and put them in a `gems/` directory via:
```shell
bundle install --path ./gems
```

## Key Bindings

In order to get goto-step-definition to work, you must install the ruby_parser gem and cucumber-gherkin:

```
gem install ruby_parser
gem install cucumber-gherkin
```

Keybinding          | Description
--------------------|------------------------------------------------------------
<kbd>C-c ,v</kbd>   | Verify all scenarios in the current buffer file.
<kbd>C-c ,s</kbd>   | Verify the scenario under the point in the current buffer.
<kbd>C-c ,f</kbd>   | Verify all features in project. (Available in feature and ruby files)
<kbd>C-c ,r</kbd>   | Repeat the last verification process.
<kbd>C-c ,g</kbd>   | Go to step-definition under point (requires ruby_parser gem >= 3.14.2)

## Supported languages

At the moment, Cucumber.el supports whatever your Cucumber
supports. If guesses the language based on the `# language: <language code>`
directive at the top of the spec.

## Support for docker-compose

If the project path contains a docker-compose.yml file, Cucumber is executed through docker-compose.

The following variables can be set to change the behavior related too this:

Variable                           |  Type   | Description
-----------------------------------|---------|-------------------------------------------
`feature-use-docker-compose`       | boolean | Use docker-compose when available
`feature-docker-compose-command`   | string  | The docker-compose command to execute
`feature-docker-compose-container` | string  | Name of the container to start Cucumber in

## Project Development / Maintenance

To run the tests in the source project, you can use the `make test`
command. If possible please use the Docker setup provided:

```sh
docker compose build
make sh # drops into a shell within the container
make test
```

## LICENSE

Copyright (C) 2008 — 2025 Michael Klishin and other contributors

You can redistribute it and/or modify it under the terms of the GNU
General Public License either version 2 of the License, or (at your
option) any later version.

This program is distributed in the hope that it will be useful,
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License if
not, write to the Free Software Foundation, Inc., 51 Franklin Street,
Suite 500, Boston, MA 02110.
