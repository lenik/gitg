/*
 * This file is part of gitg
 *
 * Copyright (C) 2012 - Jesse van den Kieboom
 *
 * gitg is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * gitg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with gitg. If not, see <http://www.gnu.org/licenses/>.
 */

namespace GitgHistory
{
	/* The main history view. This view shows the equivalent of git log, but
	 * in a nice way with lanes, merges, ref labels etc.
	 */
	public class View : Object, GitgExt.UIElement, GitgExt.View, GitgExt.ObjectSelection
	{
		// Do this to pull in config.h before glib.h (for gettext...)
		private const string version = Gitg.Config.VERSION;

		public GitgExt.Application? application { owned get; construct set; }

		private Gtk.TreeView d_view;
		private GitgGtk.CommitModel? d_model;
		private Gee.HashSet<Ggit.OId> d_selected;
		private ulong d_insertsig;

		private Gtk.Widget d_main;

		public string id
		{
			owned get { return "/org/gnome/gitg/Views/History"; }
		}

		public void foreach_selected(GitgExt.ForeachObjectSelectionFunc func)
		{
			bool breakit = false;

			d_view.get_selection().selected_foreach((model, path, iter) => {
				if (!breakit)
				{
					breakit = !func(d_model.commit_from_iter(iter));
				}
			});
		}

		construct
		{
			d_model = new GitgGtk.CommitModel(application.repository);
			d_selected = new Gee.HashSet<Ggit.OId>(Ggit.OId.hash, (EqualFunc<Ggit.OId>)Ggit.OId.equal);

			d_model.started.connect(on_commit_model_started);
			d_model.finished.connect(on_commit_model_finished);

			application.bind_property("repository", d_model, "repository", BindingFlags.DEFAULT);
		}

		private void on_commit_model_started(Gitg.CommitModel model)
		{
			if (d_selected.size > 0 && d_insertsig == 0)
			{
				d_insertsig = d_model.row_inserted.connect(on_row_inserted_select);
			}
		}

		private void on_row_inserted_select(Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter iter)
		{
			var commit = d_model.commit_from_path(path);

			if (d_selected.remove(commit.get_id()))
			{
				d_view.get_selection().select_path(path);

				if (d_selected.size == 0)
				{
					d_model.disconnect(d_insertsig);
					d_insertsig = 0;
				}
			}
		}

		private void on_commit_model_finished(Gitg.CommitModel model)
		{
			if (d_insertsig != 0)
			{
				d_model.disconnect(d_insertsig);
				d_insertsig = 0;
			}
		}

		public bool available
		{
			get
			{
				// The history view is available only when there is a repository
				return application.repository != null;
			}
		}

		public string display_name
		{
			owned get { return _("History"); }
		}

		public Icon? icon
		{
			owned get { return new ThemedIcon("view-list-symbolic"); }
		}

		public Gtk.Widget? widget
		{
			owned get
			{
				if (d_main == null)
				{
					build_ui();
				}

				return d_main;
			}
		}

		public GitgExt.Navigation? navigation
		{
			owned get
			{
				// Create the sidebar navigation for the history. This navigation
				// will show branches, remotes and tags which can be used to
				// filter the history
				var ret = new Navigation(application);

				ret.ref_activated.connect(on_ref_activated);

				return ret;
			}
		}

		public bool is_default_for(GitgExt.ViewAction action)
		{
			return application.repository != null && action == GitgExt.ViewAction.HISTORY;
		}

		private void on_ref_activated(Gitg.Ref r)
		{
			update_walker(r);
		}

		private void build_ui()
		{
			var ret = from_builder("view-history.ui", {"scrolled_window_commit_list", "commit_list_view"});

			d_view = ret["commit_list_view"] as Gtk.TreeView;
			d_view.model = d_model;

			d_view.get_selection().changed.connect((sel) => {
				selection_changed();
			});

			d_main = ret["scrolled_window_commit_list"] as Gtk.Widget;
		}

		private void update_walker(Gitg.Ref? head)
		{
			Ggit.OId? id = null;

			if (head != null)
			{
				id = head.get_id();

				if (head.parsed_name.rtype == Gitg.RefType.TAG)
				{
					// See to resolve to the commit
					try
					{
						var t = application.repository.lookup(id, typeof(Ggit.Tag)) as Ggit.Tag;

						id = t.get_target_id();
					} catch {}
				}
			}

			if (id == null && application.repository != null)
			{
				try
				{
					Gitg.Ref? th = application.repository.get_head();

					if (th != null)
					{
						id = th.get_id();
					}
				} catch {}
			}

			if (id != null)
			{
				d_selected.clear();
				d_selected.add(id);

				d_model.set_include(new Ggit.OId[] { id });
			}

			d_model.reload();
		}

		private Gee.HashMap<string, Object>? from_builder(string path, string[] ids)
		{
			var builder = new Gtk.Builder();

			try
			{
				builder.add_from_resource("/org/gnome/gitg/history/" + path);
			}
			catch (Error e)
			{
				warning("Failed to load ui: %s", e.message);
				return null;
			}

			Gee.HashMap<string, Object> ret = new Gee.HashMap<string, Object>();

			foreach (string id in ids)
			{
				ret[id] = builder.get_object(id);
			}

			return ret;
		}

		public bool enabled
		{
			get
			{
				return true;
			}
		}

		public int negotiate_order(GitgExt.UIElement other)
		{
			return -1;
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module)
{
	Peas.ObjectModule mod = module as Peas.ObjectModule;

	mod.register_extension_type(typeof(GitgExt.View),
	                            typeof(GitgHistory.View));
}

// ex: ts=4 noet
